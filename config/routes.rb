Rails.application.routes.draw do
  if Rails.env.development? && defined?(LetterOpenerWeb)
    mount LetterOpenerWeb::Engine, at: "/letter_opener"
  end

  # Health check (any host) for load balancers / uptime monitors.
  get "up" => "rails/health#show", as: :rails_health_check

  # Registers the Devise :user mapping (session auth). All routes are defined
  # explicitly per subdomain below (devise_scope :user), so skip the defaults.
  devise_for :users, skip: :all

  # Per-subdomain route files (config/routes/*.rb). Each file is self-contained
  # and wraps its declarations in its own `constraints subdomain:` block.
  draw(:login)     # login.prescsign.com    — authentication (session)
  draw(:register)  # register.prescsign.com — invitation-based registration
  draw(:app)       # app.prescsign.com      — the tenant panel
  draw(:admin)     # admin.prescsign.com    — platform back-office

  # ---------------------------------------------------------------------------
  # Public document validation (no auth, any host). Reachable from the QR code /
  # verification code printed on issued documents.
  # ---------------------------------------------------------------------------
  get "validate",       to: "public/document_validations#new",  as: :public_document_validation_search
  get "validate/:code", to: "public/document_validations#show", as: :public_document_validation

  # Download seguro do PDF assinado (token assinado com expiração — sem auth).
  # Enviado ao paciente ao assinar. O PDF nunca trafega no email, só o link.
  get "d/:token", to: "public/document_downloads#show", as: :public_document_download

  # Bare host / apex: send to the login subdomain.
  root to: redirect(subdomain: "login", path: "/"), as: :root
end
