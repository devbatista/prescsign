devise_for :doctors,
           path: "v1/auth",
           path_names: { confirmation: "confirmation" },
           controllers: { confirmations: "v1/auth/confirmations" },
           skip: [:sessions, :passwords, :registrations]

namespace :v1 do
  get "health", to: "health#show"

  scope :auth do
    post "register", to: "auth/registrations#create"
    post "login", to: "auth/sessions#create"
    post "refresh", to: "auth/refresh_tokens#create"
    delete "logout", to: "auth/sessions#destroy"
    post "password", to: "auth/passwords#create"
    put "password", to: "auth/passwords#update"
  end
end
