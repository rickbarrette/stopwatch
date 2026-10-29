require File.expand_path('../../test_helper', __FILE__)

class TimerTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  fixtures :users, :user_preferences, :time_entries

  setup do
    @user = User.find 1
    @timer = Stopwatch::Timer.new @user
    @time_entry = TimeEntry.last
    @time_entry.update_column :comments, 'work'
    Setting.plugin_stopwatch = Setting.plugin_stopwatch.merge('max_timer_hours' => '10')
  end

  # The timer re-reads its saved state under a lock, so always look at the current data
  def data
    @timer.send :data
  end

  # Pretend the timer was last saved `ago` seconds ago
  def started(ago)
    data[:started_at] = ago.ago.to_i
    @timer.save
  end

  test "should know wether its running" do
    refute @timer.running?
    data[:started_at] = 5.minutes.ago
    assert @timer.running?
  end

  test "should start timer" do
    assert_nil data[:started_at]
    @timer.start @time_entry
    assert data[:started_at].present?
    assert_equal @time_entry.id, data[:time_entry_id]
  end

  test "should stop timer and update time entry" do
    hours = @time_entry.hours
    @timer.start @time_entry
    started 1.hour
    @timer.stop

    @time_entry.reload
    assert_equal hours + 1, @time_entry.hours
    refute @timer.running?
  end

  test "should update time entry" do
    hours = @time_entry.hours
    @timer.start @time_entry
    started 1.hour
    @timer.update

    @time_entry.reload
    assert_equal hours + 1, @time_entry.hours
    assert @timer.running?
  end

  test "should save and restore" do
    hours = @time_entry.hours
    @timer.start @time_entry
    started 1.hour

    timer = Stopwatch::Timer.new User.find(@user.id)
    assert timer.running?
    timer.stop

    @time_entry.reload
    assert_equal hours + 1, @time_entry.hours
  end

  test "should not add the same time twice when updated twice" do
    hours = @time_entry.hours
    @timer.start @time_entry
    started 1.hour

    # e.g. two open tabs checking the timer at the same moment
    other_tab = Stopwatch::Timer.new User.find(@user.id)
    @timer.update
    other_tab.update

    @time_entry.reload
    assert_in_delta hours + 1, @time_entry.hours, 0.01
  end

  test "should stop a forgotten timer at the limit and flag the entry" do
    Setting.plugin_stopwatch = Setting.plugin_stopwatch.merge('max_timer_hours' => '2')
    hours = @time_entry.hours
    @timer.start @time_entry
    started 60.hours # left running over a weekend
    @timer.stop

    @time_entry.reload
    assert_equal hours + 2, @time_entry.hours
    assert_includes @time_entry.comments, 'work'
    assert_includes @time_entry.comments, '2 hour limit'
    refute @timer.running?
  end

  test "should count earlier saves toward the limit" do
    Setting.plugin_stopwatch = Setting.plugin_stopwatch.merge('max_timer_hours' => '2')
    hours = @time_entry.hours
    @timer.start @time_entry
    started 90.minutes
    @timer.update
    assert @timer.running?

    started 1.hour
    @timer.update

    @time_entry.reload
    assert_in_delta hours + 2, @time_entry.hours, 0.01
    refute @timer.running?
  end

  test "should not limit timers when the limit is blank" do
    Setting.plugin_stopwatch = Setting.plugin_stopwatch.merge('max_timer_hours' => '')
    hours = @time_entry.hours
    @timer.start @time_entry
    started 30.hours
    @timer.stop

    @time_entry.reload
    assert_in_delta hours + 30, @time_entry.hours, 0.01
  end

  test "starting again moves the timer instead of failing" do
    other_entry = TimeEntry.where.not(id: @time_entry.id).first
    hours = @time_entry.hours
    @timer.start @time_entry
    started 1.hour

    @timer.start other_entry # e.g. a double click, or starting another entry

    assert_equal other_entry.id, data[:time_entry_id]
    assert_in_delta hours + 1, @time_entry.reload.hours, 0.01
  end

  test "should schedule server-side saves while running" do
    assert_enqueued_with(job: StopwatchTimerTickJob) do
      @timer.start @time_entry
    end
  end

  test "tick job saves the time and schedules the next tick" do
    hours = @time_entry.hours
    @timer.start @time_entry
    started 1.hour
    token = data[:tick_token]

    clear_enqueued_jobs
    assert_enqueued_with(job: StopwatchTimerTickJob, args: [@user.id, token]) do
      StopwatchTimerTickJob.perform_now(@user.id, token)
    end
    assert_in_delta hours + 1, @time_entry.reload.hours, 0.01
  end

  test "tick job from an earlier start does nothing" do
    hours = @time_entry.hours
    @timer.start @time_entry
    started 1.hour

    clear_enqueued_jobs
    StopwatchTimerTickJob.perform_now(@user.id, 'old-token')
    assert_no_enqueued_jobs
    assert_equal hours, @time_entry.reload.hours
  end
end
