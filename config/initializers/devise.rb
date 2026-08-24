Devise.setup do |config|
  # Proc para resolver na hora do envio: o From: é montado por
  # Mailers::SenderAddress, que não pode ser autoloaded durante o boot.
  config.mailer_sender = ->(_scope) { Mailers::SenderAddress.default }
  config.mailer = "UserDeviseMailer"

  require "devise/orm/active_record"

  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  # Web (session) auth uses HTML navigational flow (redirects/flash); the JWT API
  # uses JSON/Bearer and stays non-navigational. Both coexist during the migration.
  config.navigational_formats = [:html]
  config.skip_session_storage = [:http_auth, :params_auth]

  # Bounce unauthenticated web requests to the login subdomain.
  config.warden do |manager|
    manager.failure_app = SubdomainFailureApp
  end
end
