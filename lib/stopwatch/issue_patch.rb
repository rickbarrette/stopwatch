module Stopwatch
  # When an issue is closed, stop any timer still running on it, so the time logged on the issue is
  # final before anything uses it (e.g. billing that runs when an issue closes). Otherwise the timer
  # would keep adding hours to an entry that was already billed.
  module IssuePatch
    extend ActiveSupport::Concern

    prepended do
      after_save :stop_timers_on_close, if: -> { saved_change_to_status_id? && closed? }
    end

    def stop_timers_on_close
      user_ids = time_entries.distinct.pluck(:user_id)
      User.where(id: user_ids).find_each do |user|
        timer = Stopwatch::Timer.new(user)
        next unless timer.running? && timer.time_entry&.issue_id == id

        timer.stop
        Rails.logger.info "[Stopwatch] Stopped user ##{user.id}'s timer because issue ##{id} was closed"
      end
    rescue StandardError => e
      # Never block closing the issue
      Rails.logger.error "[Stopwatch] Could not stop timers for issue ##{id}: #{e.class}: #{e.message}"
    end
  end
end
