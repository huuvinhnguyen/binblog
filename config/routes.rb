require 'sidekiq/web'
# require 'sidekiq/cron/web' # <- Dòng này để hiện tab "Cron"
# require 'sidekiq-scheduler/web'

Rails.application.routes.draw do
  resources :posts
  get 'home/index'
  devise_for :users
  mount ActionCable.server => '/cable'
  # mount Sidekiq::Web => '/sidekiq'
  mount Sidekiq::Web => '/sidekiq'

  namespace :api do
    resources :devices, only: [] do
      collection do
        post :receive_info
        post :add_reminder
        post :remove_reminder
        post :set_reminders_active
        get :device_info  
        post :trigger
        post :switchon
        post :set_longlast
        post :restart
        post :update_last_seen
        post :update_version
        post :reset_wifi
        post :refresh_device
      end
    end
  end

  get 'devices/index'
  get 'devices/show'
  get 'devices/new'
  get 'devices/create'
  get 'devices/edit'
  get 'devices/update'
  get 'devices/destroy'
  post 'devices/publish'
  post 'devices/connect'
  post 'devices/switchon'
  post 'devices/connect_dht', to: 'devices#connect_dht', as: 'connect_dht_devices'
  post 'devices/disconnect_mqtt', to: 'devices#disconnect_mqtt', as: 'disconnect_mqtt_devices'
  post 'devices/notify', to: 'devices#notify'
  post 'employees/activate_adding_finger'
  post 'employees/enroll_fingerprint'
  post 'checkins/create'
  post 'attendances/checkin'


  mount RailsAdmin::Engine => '/admin', as: 'rails_admin'
  get 'youtube/download_mp3'
  get 'resumes/index'
  get 'resumes/new'
  get 'resumes/create'
  get 'resumes/destroy'

  resources :widgets
  # resources :employees do
  #   get :export_xls, on: :collection
  # end
  resources :employees do
    collection do
      get :export_xls
      get :export_csv
      get :export_attendance_xls
    end
  end

  resources :employees do
    resources :attendances, only: [:create, :edit, :update, :destroy]
  end
  

  resources :employees do
    resources :rewards_penalties, only: [:new, :create, :edit, :update, :destroy]
  end
  
  resources :employees do
    member do
      delete 'attendances/:id', to: 'employees#destroy_attendance', as: 'attendance_destroy'
      get 'employees/:id', to: 'employees#show', as: 'filter_atendances'
      delete 'delete_fingerprint', to: 'employees#delete_fingerprint'
      post 'cancel_enrollment', to: 'employees#cancel_enrollment'

    end
  end
  resources :devices, only: [:index, :new, :create, :destroy, :publish]
  namespace :api do
    resources :devices, only: [:create]
  end
  # config/routes.rb
  resources :devices do
    collection do
      get :mqtt_data
      get :latest_data
    end
  end

  resources :devices do
    post 'remove_reminder_message', on: :collection
  end
  
  resources :fingers, only: [:index, :show, :new, :create, :destroy]
  resources :fingers do
    post 'delete_fingerprint_message', on: :collection
  end
  # or nested under employees
  resources :employees do
    resources :fingers, only: [:index, :show, :new, :create, :destroy]
  end

  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  # You can have the root of your site routed with "root"

  root 'home#index'


  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  resources :resumes, only: [:index, :new, :create, :destroy]
  resources :projects
  post '/download_mp3', to: 'youtube#download_mp3'
  post 'youtube/download_mp3'

  get '/youtube/download_mp3', to: 'youtube#download_mp3'
  # get '/employees/export_xls', to: 'employees#export_xls'
end
