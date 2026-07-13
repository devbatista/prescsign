# login.prescsign.com.br — authentication (session)
constraints subdomain: "login" do
  devise_scope :user do
    get    "sign-in",  to: "sessions#new",     as: :new_user_session
    post   "sign-in",  to: "sessions#create",  as: :user_session
    delete "sign-out", to: "sessions#destroy", as: :destroy_user_session

    # Password recovery. edit_user_password_url is used by the reset email.
    get  "forgot-password", to: "passwords#new",    as: :new_user_password
    post "forgot-password", to: "passwords#create", as: :user_password
    get  "reset-password",  to: "passwords#edit",   as: :edit_user_password
    put  "reset-password",  to: "passwords#update", as: :user_password_update

    # Account confirmation. The confirmation email links to web_user_confirmation_url.
    get  "confirm-account",      to: "confirmations#show",   as: :web_user_confirmation
    get  "resend-confirmation",  to: "confirmations#new",    as: :new_web_user_confirmation
    post "resend-confirmation",  to: "confirmations#create", as: :web_user_confirmation_resend
  end

  root "sessions#new", as: :login_root
end
