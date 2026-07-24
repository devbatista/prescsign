# app.prescsign.com.br — the tenant panel
constraints subdomain: "app" do
  delete "sign-out", to: "sessions#destroy"

  post "organizations/switch", to: "app/organizations#switch",                as: :switch_organization
  get  "organizations/select", to: "app/organizations#select",                as: :select_organization
  post "organizations/select", to: "app/organizations#choose",                as: :choose_organization
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

  resources :documents, controller: "app/documents", only: %i[index show] do
    member do
      patch :sign
      patch :integrity_check
      post :resend
    end
  end

  # Autenticação Gov.br (OIDC) junto ao SNCR, para obtenção de numeração.
  get "sncr/auth/start",    to: "app/sncr/auth#start",    as: :sncr_auth_start
  get "sncr/auth/callback", to: "app/sncr/auth#callback", as: :sncr_auth_callback

  resources :audit_logs, controller: "app/audit_logs", only: %i[index]

  resources :doctors, controller: "app/doctors", only: %i[index new create]

  resource :profile, controller: "app/profile", only: %i[show edit update]

  get "about", to: "app/pages#about", as: :about

  root "app/dashboard#show", as: :app_root
end
