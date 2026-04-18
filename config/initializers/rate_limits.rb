Rails.application.configure do
  test_multiplier = Rails.env.test? ? 1000 : 1

  config.x.rate_limits = {
    auth_register: {
      limit: ENV.fetch("RATE_LIMIT_AUTH_REGISTER_LIMIT", 10 * test_multiplier).to_i,
      period: ENV.fetch("RATE_LIMIT_AUTH_REGISTER_PERIOD", 10.minutes.to_i).to_i
    },
    auth_login: {
      limit: ENV.fetch("RATE_LIMIT_AUTH_LOGIN_LIMIT", 20 * test_multiplier).to_i,
      period: ENV.fetch("RATE_LIMIT_AUTH_LOGIN_PERIOD", 10.minutes.to_i).to_i
    },
    auth_refresh: {
      limit: ENV.fetch("RATE_LIMIT_AUTH_REFRESH_LIMIT", 30 * test_multiplier).to_i,
      period: ENV.fetch("RATE_LIMIT_AUTH_REFRESH_PERIOD", 10.minutes.to_i).to_i
    },
    auth_password_reset: {
      limit: ENV.fetch("RATE_LIMIT_AUTH_PASSWORD_RESET_LIMIT", 10 * test_multiplier).to_i,
      period: ENV.fetch("RATE_LIMIT_AUTH_PASSWORD_RESET_PERIOD", 10.minutes.to_i).to_i
    },
    public_document_validation: {
      limit: ENV.fetch("RATE_LIMIT_PUBLIC_DOCUMENT_VALIDATION_LIMIT", 60 * test_multiplier).to_i,
      period: ENV.fetch("RATE_LIMIT_PUBLIC_DOCUMENT_VALIDATION_PERIOD", 1.minute.to_i).to_i
    }
  }
end
