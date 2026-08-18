Rails.application.routes.draw do
  root "dashboard#index"
  get "search", to: "dashboard#index"
  get "assistant", to: "assistant#show", as: :assistant
  patch "settings/theme", to: "settings#theme", as: :theme_setting
  resource :updates, only: :show, controller: "updates" do
    post :check
    post :install
  end
  resources :maps, only: [ :index, :show ] do
    get :archive, on: :member
    get :search, on: :member
    post :reindex, on: :member
  end
  resources :documents, only: [ :index, :show, :create, :destroy ] do
    get :source_entry, on: :member
    get :source_page, on: :member
    get :zim_asset, on: :member
  end
  resource :setup, only: [ :show, :create ], controller: "setup"
  get "setup/complete", to: "setup#complete", as: :setup_complete
  resources :downloads, only: [ :index, :destroy ] do
    get :status, on: :collection
    post :retry_failed, on: :collection
    post :reindex_all, on: :collection
    post :install, on: :collection
    post :stop, on: :member
    post :retry_download, on: :member
    post :index_content, on: :member
    delete :search_index, on: :member
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
