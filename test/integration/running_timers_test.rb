require File.expand_path('../test_helper', __dir__)

class RunningTimersTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :user_preferences, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses, :issues,
           :enumerations, :time_entries

  setup do
    @issue = Issue.find 1
    @manager = User.find_by_login 'jsmith'  # Manager in project 1
    @worker = User.find_by_login 'dlopper'  # Developer in project 1
    @entry = TimeEntry.create!(project: @issue.project, issue: @issue, user: @worker, author: @worker,
                               spent_on: Date.today, hours: 1, activity: TimeEntryActivity.first)
    timer = Stopwatch::Timer.new(@worker)
    timer.start @entry
    data = timer.send(:data)
    data[:started_at] = data[:session_started_at] = 3.hours.ago.to_i
    timer.save
    Role.find(1).remove_permission!(:view_running_timers, :stop_running_timers)
    Role.find(2).remove_permission!(:view_running_timers, :stop_running_timers)
  end

  def worker_timer
    Stopwatch::Timer.new(User.find(@worker.id))
  end

  test "page needs the view permission" do
    log_user 'jsmith', 'jsmith'
    get '/stopwatch/running_timers'
    assert_response 403
  end

  test "lists running timers without a stop button when the user can only view" do
    Role.find(1).add_permission!(:view_running_timers)
    log_user 'jsmith', 'jsmith'
    get '/stopwatch/running_timers'
    assert_response :success
    assert_select "tr#stopwatch-running-timer-#{@worker.id} td.user", text: /#{@worker.name}/
    assert_select "tr#stopwatch-running-timer-#{@worker.id} td.started", text: /\d/
    assert_select "tr#stopwatch-running-timer-#{@worker.id} form.stopwatch-stop-form", 0
  end

  test "stopping someone else's timer needs the stop permission" do
    Role.find(1).add_permission!(:view_running_timers)
    log_user 'jsmith', 'jsmith'
    post "/stopwatch/running_timers/#{@worker.id}/stop"
    assert_response 403
    assert worker_timer.running?
  end

  test "manager stops a forgotten timer at the time the person left" do
    Role.find(1).add_permission!(:view_running_timers, :stop_running_timers)
    log_user 'jsmith', 'jsmith'
    get '/stopwatch/running_timers'
    assert_select "tr#stopwatch-running-timer-#{@worker.id} form.stopwatch-stop-form"

    left_at = (2.hours.ago).in_time_zone(Time.zone).strftime('%Y-%m-%dT%H:%M') # 1 hour after starting
    post "/stopwatch/running_timers/#{@worker.id}/stop", params: { stopped_at: left_at }
    assert_redirected_to '/stopwatch/running_timers'

    refute worker_timer.running?
    @entry.reload
    assert_in_delta 2.0, @entry.hours, 0.02 # 1 hour before + 1 hour of this run
    assert_includes @entry.comments, "Timer stopped by #{@manager.name}"
  end

  test "stopping without a time stops now" do
    Role.find(1).add_permission!(:view_running_timers, :stop_running_timers)
    log_user 'jsmith', 'jsmith'
    post "/stopwatch/running_timers/#{@worker.id}/stop"
    refute worker_timer.running?
    assert_in_delta 4.0, @entry.reload.hours, 0.02
  end

  test "users with view permission can stop their own timer" do
    Role.find(2).add_permission!(:view_running_timers)
    log_user 'dlopper', 'foo'
    post "/stopwatch/running_timers/#{@worker.id}/stop"
    refute worker_timer.running?
    refute_includes @entry.reload.comments.to_s, 'Timer stopped by'
  end

  test "timers in other projects are not shown" do
    Role.find(1).add_permission!(:view_running_timers)
    @entry.update_columns(project_id: 2, issue_id: nil) # jsmith has no view_running_timers in project 2
    log_user 'jsmith', 'jsmith'
    get '/stopwatch/running_timers'
    assert_select "tr#stopwatch-running-timer-#{@worker.id}", 0
  end
end
