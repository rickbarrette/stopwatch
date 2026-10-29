Redmine::Plugin.register :stopwatch do
  name 'Redmine Stopwatch Plugin'
  author 'Jens Krämer'
  author_url 'https://jkraemer.net/'
  description "Start/stop timer and quick access to today's time bookings for Redmine"
  version '2026.10.1'

  requires_redmine version_or_higher: '7.0.0'
  settings default: {
    'default_activity' => 'always_ask',
    'highlighted_links' => '0',
    'max_timer_hours' => '10',
  }, partial: 'stopwatch/settings'

  # Running timers page: see everyone's running timers, and stop one someone forgot. Both are role
  # permissions, so they apply to timers on time entries in the projects where the role has them.
  permission :view_running_timers, { stopwatch_running_timers: [:index] }
  permission :stop_running_timers, { stopwatch_running_timers: [:stop] }

  menu :top_menu, :stopwatch_running_timers,
    { controller: 'stopwatch_running_timers', action: 'index' },
    caption: :label_stopwatch_running_timers,
    if: ->(*_){ User.current.allowed_to?(:view_running_timers, nil, global: true) }

  menu :account_menu, :stopwatch,
    :new_stopwatch_timer_path,
    caption: :button_log_time,
    html: { method: :get, id: 'stopwatch-menu', 'data-remote': true },
    before: :my_account,
    if: ->(*_){ User.current.logged? and User.current.allowed_to?(:log_time, nil, global: true) }
end

Stopwatch.setup