Rails.application.routes.draw do
  mount ActionCable.server => '/cable'

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
      get :export_attendance_xls
    end
  end

  resources :employees do
    resources :attendances, only: [:create]
  end
  resources :employees do
    member do
      delete 'attendances/:id', to: 'employees#destroy_attendance', as: 'attendance_destroy'
      get 'employees/:id', to: 'employees#show', as: 'filter_atendances'

    end
  end
  resources :devices, only: [:index, :new, :create, :destroy, :publish]
  # config/routes.rb
  resources :devices do
    collection do
      get :mqtt_data
      get :latest_data

    end
  end






  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  # You can have the root of your site routed with "root"

  #root 'welcome#index'

  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  resources :resumes, only: [:index, :new, :create, :destroy]
  resources :projects
  root "employees#index"
  post '/download_mp3', to: 'youtube#download_mp3'
  post 'youtube/download_mp3'

  get '/youtube/download_mp3', to: 'youtube#download_mp3'
  # get '/employees/export_xls', to: 'employees#export_xls'
end
