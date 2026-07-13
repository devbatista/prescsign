# app.prescsign.com.br — the tenant panel
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
