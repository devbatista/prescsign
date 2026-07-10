Rails.application.routes.draw do
  if Rails.env.development? && defined?(LetterOpenerWeb)
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  # Define your application routes per the DSL in https://guides.rubyonrails.org/routing.html

  # Reveal health status on /up that returns 200 if the app boots with no exceptions, otherwise 500.
  # Can be used by load balancers and uptime monitors to verify that the app is live.
  get "up" => "rails/health#show", as: :rails_health_check

  # Official versioned prefix.
  scope :api, as: :api do
    draw :api
  end

  # Backward compatibility with existing /v1 routes.
  draw :api

  # Web layer (server-rendered ERB, session auth).
  devise_scope :user do
    get    "entrar", to: "sessions#new",     as: :new_user_session
    post   "entrar", to: "sessions#create",  as: :user_session
    delete "sair",   to: "sessions#destroy", as: :destroy_user_session
  end

  root "dashboard#show"
end
