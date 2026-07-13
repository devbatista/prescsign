# admin.prescsign.com.br — platform back-office (cross-org, super_admin/support)
constraints subdomain: "admin" do
  root "admin/dashboard#show", as: :admin_root
end
