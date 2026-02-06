Rails.application.routes.draw do
  # Dashboard routes
  namespace :dashboard do
    get "sign_in", to: "sessions#new"
    post "sign_in", to: "sessions#create"
    delete "sign_out", to: "sessions#destroy"
    get "sign_up", to: "registrations#new"
    post "sign_up", to: "registrations#create"
    
    get "account", to: "account#show", as: :account
    post "account/regenerate_api_key", to: "account#regenerate_api_key", as: :regenerate_api_key
    patch "account/credentials", to: "account#update_credentials", as: :update_credentials
    
    get "overview", to: "overview#index", as: :overview
    resources :transactions, only: [:index]
    resources :payment_intents, only: [:index, :show]
    resources :ledger, only: [:index], controller: "ledger"
    resources :webhooks, only: [:index], controller: "webhooks"
    
    root to: "overview#index"
  end
  
  root to: "dashboard/sessions#new"

  # API routes
  namespace :api do
    namespace :v1 do
      get "health", to: "health#show"

      # Merchants
      post "merchants", to: "merchants#create"
      get "merchants/me", to: "merchants#me"

      # Customers
      resources :customers, only: [:index, :show, :create] do
        # Payment Methods
        resources :payment_methods, only: [:create], controller: "payment_methods"
      end

      # Payment Intents
      resources :payment_intents, only: [:index, :show, :create] do
        member do
          post "authorize"
          post "capture"
          post "void"
        end
        # Refunds
        resources :refunds, only: [:create], controller: "refunds"
      end

      # Webhooks
      post "webhooks/processor", to: "webhooks#processor"
    end
  end
end
