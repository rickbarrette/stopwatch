module Stopwatch
  module TimeEntryPatch
    extend ActiveSupport::Concern

    prepended do
      before_destroy :stop_timer
    end

    # Stop the user's timer only if it is running on this entry (deleting another entry used to stop it)
    def stop_timer
      t = Stopwatch::Timer.new(user)
      t.update(stop: true) if t.running? && t.time_entry_id == id
    end
  end
end
