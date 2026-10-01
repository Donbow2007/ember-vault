Rails.application.routes.draw do
  root "dashboard#index"
  get "search", to: "dashboard#index"
  resource :onboarding, only: :show, controller: "onboarding" do
    post :complete
  end
  get "assistant", to: "assistant#show", as: :assistant
  post "assistant", to: "assistant#create"
  get "assistant/responses/:id", to: "assistant#status", as: :assistant_response
  post "assistant/responses/:id/cancel", to: "assistant#cancel", as: :cancel_assistant_response
  patch "settings/theme", to: "settings#theme", as: :theme_setting
  resource :updates, only: :show, controller: "updates" do
    post :check
    post :install
  end
  resources :models, only: [ :index, :destroy ] do
    post :install, on: :member
    get :install_stream, on: :member
  end
  resources :maps, only: [ :index, :show ] do
    get :archive, on: :member
    get :search, on: :member
    post :reindex, on: :member
  end
  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Render dynamic PWA files from app/views/pwa/* (remember to link manifest in application.html.erb)
  # get "manifest" => "rails/pwa#manifest", as: :pwa_manifest
  # get "service-worker" => "rails/pwa#service_worker", as: :pwa_service_worker

  # Defines the root path route ("/")
  # root "posts#index"
end
