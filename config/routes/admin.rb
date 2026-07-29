# admin.prescsign.com.br — platform back-office (cross-org, super_admin/support)
constraints subdomain: "admin" do
  delete "sign-out", to: "sessions#destroy"

  # Módulos do back-office. `scope module: "admin", as: :admin` mantém os
  # controllers em Admin:: e prefixa os helpers com `admin_` (evita colisão com
  # os helpers `organizations` do subdomínio app.).
  scope module: "admin", as: :admin do
    resources :organizations, only: %i[index show] do
      member do
        patch :activate
        patch :deactivate
      end
    end
  end

  root "admin/dashboard#show", as: :admin_root
end
