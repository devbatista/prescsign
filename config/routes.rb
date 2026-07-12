Rails.application.routes.draw do
  if Rails.env.development? && defined?(LetterOpenerWeb)
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  # Health check (any host) for load balancers / uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  # ---------------------------------------------------------------------------
  # JWT API (unchanged during the migration). Served on api.prescsign.local and
  # on the bare host (localhost) for existing clients/tests. Removed in Fase 5.
  # ---------------------------------------------------------------------------
  scope :api, as: :api do
    draw :api
  end
  draw :api

  # ---------------------------------------------------------------------------
  # login.prescsign.local — authentication (session)
  # ---------------------------------------------------------------------------
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

  # ---------------------------------------------------------------------------
  # register.prescsign.local — invitation-based registration
  # ---------------------------------------------------------------------------
  constraints subdomain: "register" do
    devise_scope :user do
      get  "sign-up", to: "registrations#new",    as: :new_user_registration
      post "sign-up", to: "registrations#create", as: :user_registration
    end

    root "registrations#new", as: :register_root
  end

  # ---------------------------------------------------------------------------
  # app.prescsign.local — the tenant panel
  # ---------------------------------------------------------------------------
  constraints subdomain: "app" do
    post "organizations/switch", to: "app/organizations#switch",                as: :switch_organization
    get  "no-organization",      to: "app/pages#organization_context_required", as: :organization_context_required

    resources :organizations, controller: "app/organizations", only: %i[new create]

    resources :patients, controller: "app/patients"

    resources :consultations, controller: "app/consultations", except: %i[destroy] do
      member { patch :cancel }
    end

    get "agenda", to: "app/agenda/events#index", as: :agenda

    resources :prescriptions, controller: "app/prescriptions", only: %i[new create edit update] do
      member do
        patch :revoke
        get :pdf
      end
    end

    resources :medical_certificates, controller: "app/medical_certificates", only: %i[new create edit update] do
      member do
        patch :revoke
        get :pdf
      end
    end

    resources :documents, controller: "app/documents", only: %i[show] do
      member do
        patch :sign
        patch :integrity_check
        post :resend
      end
    end

    resources :audit_logs, controller: "app/audit_logs", only: %i[index]

    resources :responsible_doctors, controller: "app/responsible_doctors", only: %i[index new create]

    resource :profile, controller: "app/profile", only: %i[show edit update]

    get "about", to: "app/pages#about", as: :about

    root "app/dashboard#show", as: :app_root
  end

  # ---------------------------------------------------------------------------
  # admin.prescsign.local — platform back-office (cross-org, super_admin/support)
  # ---------------------------------------------------------------------------
  constraints subdomain: "admin" do
    root "admin/dashboard#show", as: :admin_root
  end

  # ---------------------------------------------------------------------------
  # Public document validation (no auth, any host). Reachable from the QR code /
  # verification code printed on issued documents.
  # ---------------------------------------------------------------------------
  get "validate",       to: "public/document_validations#new",  as: :public_document_validation_search
  get "validate/:code", to: "public/document_validations#show", as: :public_document_validation

  # Bare host / apex: send to the login subdomain.
  root to: redirect(subdomain: "login", path: "/"), as: :root
end
