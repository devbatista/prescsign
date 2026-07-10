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
    # Session
    get    "entrar", to: "sessions#new",     as: :new_user_session
    post   "entrar", to: "sessions#create",  as: :user_session
    delete "sair",   to: "sessions#destroy", as: :destroy_user_session

    # Password recovery (recoverable). edit_user_password_url is used by the reset email.
    get  "esqueci-senha",    to: "passwords#new",    as: :new_user_password
    post "esqueci-senha",    to: "passwords#create", as: :user_password
    get  "redefinir-senha",  to: "passwords#edit",   as: :edit_user_password
    put  "redefinir-senha",  to: "passwords#update", as: :user_password_update

    # Account confirmation (web). The confirmation email links to web_user_confirmation_url.
    get  "confirmar-conta",       to: "confirmations#show",   as: :web_user_confirmation
    get  "reenviar-confirmacao",  to: "confirmations#new",    as: :new_web_user_confirmation
    post "reenviar-confirmacao",  to: "confirmations#create", as: :web_user_confirmation_resend

    # Registration (invitation-based)
    get  "cadastro", to: "registrations#new",    as: :new_user_registration
    post "cadastro", to: "registrations#create", as: :user_registration
  end

  root "dashboard#show"
end
