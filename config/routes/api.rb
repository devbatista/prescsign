scope :v1 do
  post "auth/register", to: "auth/registrations#create"
  post "auth/login", to: "auth/sessions#create"
  post "auth/refresh", to: "auth/refresh_tokens#create"
  delete "auth/logout", to: "auth/sessions#destroy"
  post "auth/password", to: "auth/passwords#create"
  put "auth/password", to: "auth/passwords#update"
end
