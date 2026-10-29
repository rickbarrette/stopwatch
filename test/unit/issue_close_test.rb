require File.expand_path('../../test_helper', __FILE__)

class IssueCloseTest < ActiveSupport::TestCase
  fixtures :projects, :users, :user_preferences, :roles, :members, :member_roles,
           :trackers, :projects_trackers, :enabled_modules, :issue_statuses, :issues,
           :enumerations, :time_entries

  setup do
    @user = User.find 2
    @issue = Issue.find 1
    @time_entry = TimeEntry.create!(project: @issue.project, issue: @issue, user: @user, author: @user,
                                    spent_on: Date.today, hours: 1, activity: TimeEntryActivity.first)
    @timer = Stopwatch::Timer.new(@user)
    @timer.start @time_entry
    data = @timer.send(:data)
    data[:started_at] = 1.hour.ago.to_i
    @timer.save
  end

  test "closing an issue stops a timer running on it and saves the time" do
    @issue.status = IssueStatus.where(is_closed: true).first
    @issue.save!

    refute Stopwatch::Timer.new(User.find(@user.id)).running?
    assert_in_delta 2, @time_entry.reload.hours, 0.01
  end

  test "other changes to the issue leave the timer running" do
    @issue.subject = 'Renamed'
    @issue.save!

    assert Stopwatch::Timer.new(User.find(@user.id)).running?
  end

  test "deleting another time entry leaves the timer running" do
    other = TimeEntry.create!(project: @issue.project, issue: @issue, user: @user, author: @user,
                              spent_on: Date.today, hours: 1, activity: TimeEntryActivity.first)
    other.destroy

    assert Stopwatch::Timer.new(User.find(@user.id)).running?
  end
end
