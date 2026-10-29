resources :stopwatch_timers, only: %i(new create edit update) do
  collection do
    get :current
    post :update_form
  end
  member do
    put :start
    put :stop
  end
end

get 'stopwatch/running_timers', to: 'stopwatch_running_timers#index', as: :stopwatch_running_timers
post 'stopwatch/running_timers/:user_id/stop', to: 'stopwatch_running_timers#stop', as: :stop_stopwatch_running_timer

scope 'issues/:issue_id' do
  post 'timer/start', to: 'stopwatch_issue_timers#start', as: :start_issue_timer
  post 'timer/stop',  to: 'stopwatch_issue_timers#stop',  as: :stop_issue_timer
end

