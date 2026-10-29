module Stopwatch
  # Everyone's running timers, for the running timers page.
  class RunningTimers
    Row = Struct.new(:user, :timer, :time_entry, keyword_init: true) do
      def project
        time_entry&.project
      end

      def issue
        time_entry&.issue
      end

      def started_at
        timer.session_started_at
      end

      # Whether viewer may stop this timer: their own, or with "Stop running timers" in its project
      def stoppable_by?(viewer)
        return true if user == viewer
        return viewer.admin? if project.nil?

        viewer.allowed_to?(:stop_running_timers, project)
      end
    end

    # Running timers the viewer may see: their own, plus timers on entries in projects where they have
    # "View running timers". Oldest first, so forgotten timers are at the top.
    def self.visible_to(viewer)
      all.select do |row|
        row.user == viewer ||
          (row.project ? viewer.allowed_to?(:view_running_timers, row.project) : viewer.admin?)
      end
    end

    def self.all
      # Timers live in each user's preferences; only rows mentioning a timer are loaded
      UserPreference.where('others LIKE ?', '%current_timer%').includes(:user).filter_map do |pref|
        user = pref.user
        next unless user

        timer = Timer.new(user)
        next unless timer.running?

        Row.new(user: user, timer: timer, time_entry: timer.time_entry)
      end.sort_by { |row| [row.started_at ? 0 : 1, row.started_at.to_i, row.user.name] }
    end
  end
end
