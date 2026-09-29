Rails.application.routes.draw do
  root "documents#index"

  resource :session, only: :update
  resources :ocr_imports, only: :create
  resources :citations, only: :index

  resources :documents, only: %i[ index show edit update ] do
    scope module: :documents do
      resource :provenance, only: :show
      resources :corrections, only: :index
    end
  end

  get "up" => "rails/health#show", as: :rails_health_check
end
