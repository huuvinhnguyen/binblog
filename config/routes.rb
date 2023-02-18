Rails.application.routes.draw do
  resources :employees
  get 'youtube/download_mp3'
  get 'resumes/index'
  get 'resumes/new'
  get 'resumes/create'
  get 'resumes/destroy'
  resources :widgets

  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  # You can have the root of your site routed with "root"

  #root 'welcome#index'

  # For details on the DSL available within this file, see http://guides.rubyonrails.org/routing.html
  resources :resumes, only: [:index, :new, :create, :destroy]
  root "resumes#index"
  post '/download_mp3', to: 'youtube#download_mp3'
  post 'youtube/download_mp3'

  get '/youtube/download_mp3', to: 'youtube#download_mp3'
end
