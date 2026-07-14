# admin.prescsign.com.br — platform back-office (cross-org, super_admin/support)
constraints subdomain: "admin" do
  delete "sign-out", to: "sessions#destroy"

  root "admin/dashboard#show", as: :admin_root
end
