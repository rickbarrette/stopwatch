require 'json'
require 'securerandom'

module Stopwatch
  # A user's running timer. Stored as JSON in the user's preferences:
  #   started_at     - when time was last saved into the time entry (nil when stopped)
  #   time_entry_id  - the time entry the timer adds to
  #   session_hours  - hours already added since the timer was started, for the maximum timer length
  #   tick_token     - identifies this start's chain of server-side saves (StopwatchTimerTickJob)
  #   session_started_at - when the timer was started (started_at moves forward with every save)
  class Timer
    class HourFormatter
      include ApplicationHelper

      def initialize(s)
        @s = s
      end

      def html_hours
        super format_hours
      end

      def format_hours
        super @s
      end
    end

    attr_reader :user

    def initialize(user)
      @user = user
    end

    def running?
      data[:started_at].present?
    end

    # Starts the timer on time_entry. If a timer is already running (e.g. after a double click), its
    # time is saved and the timer moves to the new entry, instead of failing.
    def start(time_entry = nil)
      token = SecureRandom.hex(8)
      locked do
        apply_elapsed_time(stop: true) if running?
        data[:started_at] = Time.now.to_i
        data[:session_hours] = 0.0
        data[:time_entry_id] = time_entry&.id
        data[:tick_token] = token
        data[:session_started_at] = data[:started_at]
        save
      end
      # Keep saving the time on the server every minute while it runs
      StopwatchTimerTickJob.schedule(user.id, token)
    end

    def stop
      update stop: true
    end

    # Stops the timer for someone else (e.g. a manager on the running timers page).
    # at:  when the timer should have stopped, e.g. when the person actually left. Hours logged after
    #      that are taken back off the entry. Must be between the start and now; nil means now.
    # by:  the user stopping it; noted in the entry's comment.
    # Returns the hours this timer session ends up with, or nil if the timer wasn't running.
    def stop_for(at: nil, by: nil)
      locked do
        return nil unless running?

        started = session_started_at
        total = session_hours # before saving, so a timer at its limit is trimmed correctly too
        apply_elapsed_time(stop: true)
        save

        entry = time_entry # fresh copy, after the elapsed time was saved
        keep = total
        stopped_at = Time.now
        if entry && at && started
          stopped_at = Time.at(at.to_i.clamp(started.to_i, Time.now.to_i))
          keep = [(stopped_at - started).to_f / 1.hour, total].min
          excess = total - keep
          entry.update_columns(hours: [entry.read_attribute(:hours).to_f - excess, 0].max) if excess.positive?
        end

        if entry && by && by != user
          zone = user.time_zone || Time.zone
          note = I18n.t(:text_stopwatch_timer_stopped_by, name: by.name,
                        time: stopped_at.in_time_zone(zone).strftime('%Y-%m-%d %H:%M'))
          entry.update_columns(comments: [entry.comments.to_s.presence, note].compact.join(' ').truncate(1024))
        end

        Rails.logger.info "[Stopwatch] Timer for user ##{user.id} stopped by #{by ? "user ##{by.id}" : 'system'}, #{keep.round(2)}h kept"
        keep
      end
    end

    # When this timer was started, or nil for timers started before the start time was recorded
    def session_started_at
      ts = data[:session_started_at]
      ts.present? ? Time.at(ts.to_i) : nil
    end

    # Hours this timer has run since it was started (saved plus unsaved, never beyond the limit)
    def session_hours
      data[:session_hours].to_f + unsaved_hours
    end

    # Saves the time elapsed since the last save into the time entry, then stops the timer
    # (stop: true) or keeps it running from now. The timer record is locked meanwhile, so two requests
    # at the same moment (e.g. two open tabs) can't add the same time twice. Once a timer reaches the
    # maximum timer length it is stopped at the limit and the entry's comment says so.
    def update(stop: false)
      locked do
        if running?
          apply_elapsed_time(stop: stop)
          save
        end
      end
    end

    def tick_token
      data[:tick_token]
    end

    # True when the running timer has reached the maximum timer length and should be stopped
    def over_limit?
      max = Stopwatch.max_timer_hours
      running? && max.present? && data[:session_hours].to_f + (runtime_hours || 0) >= max
    end

    # Hours to display: what's saved on the entry plus the running time (never beyond the limit)
    def time_spent
      h = unsaved_hours
      if e = time_entry
        h += e.hours
      end
      h
    end

    def to_json
      formatter = HourFormatter.new(time_spent)
      {
        time_entry_id: time_entry_id,
        time_spent: formatter.format_hours,
        html_time_spent: formatter.html_hours,
        running: running?,
        issue_id: time_entry&.issue_id
      }.to_json
    end

    def save
      user.pref[:current_timer] = data.to_json
      user.pref.save
    end

    def time_entry_id
      data[:time_entry_id]
    end

    def time_entry
      TimeEntry.find_by_id(time_entry_id)
    end

    private

    def data
      @data ||= (t = user.pref[:current_timer]) ? JSON.parse(t).symbolize_keys : {}
    end

    # Runs the block with the user's preference row locked, after re-reading the saved timer
    def locked
      pref = user.pref
      pref.save! if pref.new_record?
      pref.with_lock do
        @data = nil
        yield
      end
    end

    # Running time not yet saved into the entry, limited by the maximum timer length
    def unsaved_hours
      hours = runtime_hours || 0
      max = Stopwatch.max_timer_hours
      max ? [hours, [max - data[:session_hours].to_f, 0].max].min : hours
    end

    def apply_elapsed_time(stop:)
      hours = unsaved_hours
      capped = over_limit?
      entry = time_entry

      if entry && (hours.positive? || capped)
        attributes = {}
        attributes[:hours] = entry.read_attribute(:hours).to_f + hours if hours.positive?
        attributes[:comments] = capped_comment(entry) if capped
        entry.update_columns(attributes) if attributes.any?
      end

      if stop || capped
        Rails.logger.info "[Stopwatch] Timer for user ##{user.id} stopped at the #{Stopwatch.max_timer_hours}h limit" if capped
        data[:started_at] = nil
        data[:session_hours] = 0.0
        data[:session_started_at] = nil
      else
        data[:started_at] = Time.now.to_i
        data[:session_hours] = data[:session_hours].to_f + hours
      end
    end

    # Notes on the entry that the timer hit the limit, so someone can correct the hours
    def capped_comment(entry)
      note = I18n.t(:text_stopwatch_timer_capped, hours: Stopwatch.max_timer_hours.to_s.sub(/\.0\z/, ''))
      comments = entry.comments.to_s
      return comments if comments.include?(note)

      [comments.presence, note].compact.join(' ').truncate(1024)
    end

    def runtime_hours
      if start = data[:started_at]
        runtime = Time.now.to_i - start
        return runtime.to_f / 1.hour
      end
    end
  end
end
