Devise.setup do |config|
  config.secret_key = Rails.application.config.x.jwt_secret_key
  config.mailer_sender = Rails.application.config.x.sendgrid.from_email
  config.mailer = "DoctorDeviseMailer"

  require "devise/orm/active_record"

  config.case_insensitive_keys = [:email]
  config.strip_whitespace_keys = [:email]
  config.navigational_formats = []
  config.skip_session_storage = [:http_auth, :params_auth]

  config.jwt do |jwt|
    jwt.secret = Rails.application.config.x.jwt_secret_key
    jwt.expiration_time = 24.hours.to_i
  end
end
