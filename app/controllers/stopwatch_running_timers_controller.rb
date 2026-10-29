# Lists everyone's running timers, and lets managers stop a timer someone forgot (optionally at the
# time they actually stopped working).
class StopwatchRunningTimersController < StopwatchController
  before_action :authorize_view

  def index
    @rows = Stopwatch::RunningTimers.visible_to(User.current)
  end

  def stop
    owner = User.find_by(id: params[:user_id])
    return render_404 unless owner

    timer = Stopwatch::Timer.new(owner)
    unless timer.running?
      flash[:warning] = l(:notice_stopwatch_timer_not_running, name: owner.name)
      return redirect_to stopwatch_running_timers_path
    end

    row = Stopwatch::RunningTimers::Row.new(user: owner, timer: timer, time_entry: timer.time_entry)
    return deny_access unless row.stoppable_by?(User.current)

    stop_at = nil
    if params[:stopped_at].present?
      stop_at = parse_user_time(params[:stopped_at])
      unless stop_at
        flash[:error] = l(:error_stopwatch_invalid_stop_time)
        return redirect_to stopwatch_running_timers_path
      end
    end

    hours = timer.stop_for(at: stop_at, by: User.current)
    flash[:notice] = l(:notice_stopwatch_timer_stopped_for, name: owner.name, hours: format_hours(hours.to_f))
    redirect_to stopwatch_running_timers_path
  end

  private

  def authorize_view
    User.current.allowed_to?(:view_running_timers, nil, global: true) or deny_access
  end

  # The "stopped at" field is a local date and time in the viewer's time zone
  def parse_user_time(value)
    (User.current.time_zone || Time.zone).parse(value.to_s)
  rescue ArgumentError
    nil
  end
end
