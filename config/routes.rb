Rails.application.routes.draw do
  get "up" => "rails/health#show", as: :rails_health_check

  get "login", to: "sessions#new"
  post "login", to: "sessions#create"
  delete "logout", to: "sessions#destroy"

  get "register", to: "registrations#new"
  post "register", to: "registrations#create"

  root "users#index"
  patch "users/block", to: "users#block", as: :block_users
  patch "users/unblock", to: "users#unblock", as: :unblock_users
  delete "users", to: "users#destroy_selected", as: :destroy_users

  post "assistant", to: "assistant#create", defaults: { format: :json }
end
