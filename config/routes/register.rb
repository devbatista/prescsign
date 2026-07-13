# register.prescsign.com.br — invitation-based registration
constraints subdomain: "register" do
  devise_scope :user do
    get  "sign-up", to: "registrations#new",    as: :new_user_registration
    post "sign-up", to: "registrations#create", as: :user_registration
  end

  root "registrations#new", as: :register_root
end
