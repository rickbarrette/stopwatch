# frozen_string_literal: true

module Stopwatch
  def self.setup
    Stopwatch::IssuesControllerPatch.apply
    ::TimeEntry.prepend Stopwatch::TimeEntryPatch
    ::Issue.prepend Stopwatch::IssuePatch
    ::User.prepend Stopwatch::UserPatch
    Stopwatch::Hooks # just load it
  end

  def self.settings
    Setting.plugin_stopwatch
  end

  def self.default_activity
    if id = settings['default_activity'].presence
      if id.to_s =~ /^\d+$/
        TimeEntryActivity.find_by_id id
      else
        id
      end
    end
  end

  def self.default_activity_for(time_entry)
    default = Stopwatch.default_activity
    return nil if default == 'always_ask'

    project = time_entry.project || time_entry.issue&.project

    if project.nil?
      activities = TimeEntryActivity.shared.active
    else
      activities = project.activities
    end

    if default == 'system'
      activities.detect(&:is_default?) || activities.detect{|a| a.parent&.is_default?} || (activities.one? && activities[0]).presence
    else
      return activities.detect{ |a| a == default || a.parent == default }
    end
  end

  # Longest a timer may run before it is stopped automatically (hours), or nil for no limit.
  # Protects against a forgotten timer adding a night or weekend to a time entry.
  def self.max_timer_hours
    value = settings['max_timer_hours']
    return 10.0 if value.nil? # setting never saved: use the default
    hours = value.to_s.strip.tr(',', '.').to_f
    hours.positive? ? hours : nil
  end

  # Closing time (stop time), as [hour, minute], or nil when none is set. Timers started before closing
  # stop at closing time; timers started after closing (overtime) keep running.
  def self.stop_time
    value = settings['stop_time'].to_s.strip
    return nil unless (m = value.match(/\A(\d{1,2}):(\d{2})\z/))

    hour, minute = m[1].to_i, m[2].to_i
    hour < 24 && minute < 60 ? [hour, minute] : nil
  end

  # Closing time on the day of the given time, in the user's time zone, or nil when no stop time is set
  def self.closing_time_on(time, user)
    hour, minute = stop_time
    return nil unless hour

    zone = user.time_zone || Time.zone
    day = time.in_time_zone(zone)
    zone.local(day.year, day.month, day.day, hour, minute)
  end

  # Colour-code the issue Start/Stop links (green to start, red to stop)
  def self.highlighted_links
    settings['highlighted_links'].to_s == '1'
  end
end
