devise_for :users,
           path: "v1/auth",
           path_names: { confirmation: "confirmation" },
           controllers: { confirmations: "v1/auth/confirmations" },
           skip: [:sessions, :passwords, :registrations]

namespace :v1 do
  get "health", to: "health#show"
  namespace :public do
    get "documents/:code/validation", to: "document_validations#show"
  end
  resources :patients, only: %i[index show create update destroy]
  resources :prescriptions, only: %i[show create update] do
    get :pdf, on: :member
    post :revoke, on: :member
  end
  resources :medical_certificates, only: %i[show create update] do
    get :pdf, on: :member
    post :revoke, on: :member
  end
  resources :documents, only: %i[show] do
    post :sign, on: :member
    post :integrity_check, on: :member
    post :resend, on: :member
  end
  resources :audit_logs, only: %i[index]
  get "organizations", to: "organizations#index"
  post "organizations", to: "organizations#create"
  post "organizations/:organization_id/switch", to: "organizations#switch"

  scope :auth do
    get "register/validate", to: "auth/registrations#validate"
    post "register", to: "auth/registrations#create"
    get "me", to: "doctors#show"
    put "me", to: "doctors#update"
    patch "me", to: "doctors#update"
    delete "me", to: "doctors#destroy"
    post "login", to: "auth/sessions#create"
    post "refresh", to: "auth/refresh_tokens#create"
    delete "logout", to: "auth/sessions#destroy"
    post "password", to: "auth/passwords#create"
    put "password", to: "auth/passwords#update"
  end
end
