# Saves a running timer's time into its time entry every minute on the server, so the issue shows the
# hours live even when nobody has Redmine open, and a forgotten timer is stopped at the maximum timer
# length on time. Each start gets its own chain of jobs (identified by a token); a chain ends when the
# timer stops or is restarted. Pending jobs are lost if Redmine restarts with the default in-process
# job runner; the next start, or an open tab's once-a-minute check, keeps the time up to date meanwhile.
class StopwatchTimerTickJob < ActiveJob::Base
  queue_as :default

  INTERVAL = 1.minute

  # Schedules the next tick, if the job backend supports delayed jobs (the :inline backend doesn't)
  def self.schedule(user_id, token)
    set(wait: INTERVAL).perform_later(user_id, token)
  rescue NotImplementedError => e
    Rails.logger.info "[Stopwatch] Server-side timer saving unavailable with this job backend: #{e.message}"
  end

  def perform(user_id, token)
    user = User.find_by(id: user_id)
    return unless user

    timer = Stopwatch::Timer.new(user)
    return unless timer.running? && timer.tick_token == token

    timer.update
    self.class.schedule(user_id, token) if timer.running? && timer.tick_token == token
  rescue StandardError => e
    Rails.logger.error "[Stopwatch] Timer tick failed for user ##{user_id}: #{e.class}: #{e.message}"
  end
end
