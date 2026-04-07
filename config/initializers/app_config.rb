module Prescsign
  module AppConfig
    module_function

    def string(key, default: nil)
      value = ENV.fetch(key, nil)
      return default if value.nil?

      stripped = value.strip
      stripped.empty? ? default : stripped
    end

    def require!(key)
      value = string(key)
      return value unless value.nil?

      raise KeyError, "Missing required environment variable: #{key}"
    end

    def require_in_production!(key)
      return string(key) unless Rails.env.production?

      require!(key)
    end

    def apply!(config)
      apply_core!(config)
      apply_integrations!(config)
      validate_integrations!
    end

    def apply_core!(config)
      apply_app_endpoint!(config)
      config.x.redis_url = string("REDIS_URL", default: "redis://localhost:6379/1")
      config.x.jwt_secret_key = jwt_secret_key
    end

    def apply_integrations!(config)
      config.x.object_storage = object_storage_options
      config.x.sendgrid = sendgrid_options
      config.x.twilio = twilio_options
      config.x.whatsapp = whatsapp_options
      config.x.sentry = sentry_options
    end

    def object_storage_options
      options = ActiveSupport::OrderedOptions.new
      options.enabled = string("S3_BUCKET").present?
      options.access_key_id = string("S3_ACCESS_KEY_ID")
      options.secret_access_key = string("S3_SECRET_ACCESS_KEY")
      options.region = string("S3_REGION", default: "us-east-1")
      options.bucket = string("S3_BUCKET")
      options.endpoint = string("S3_ENDPOINT")
      options
    end

    def sendgrid_options
      options = ActiveSupport::OrderedOptions.new
      options.enabled = string("SENDGRID_API_KEY").present?
      options.api_key = string("SENDGRID_API_KEY")
      options.from_email = string("SENDGRID_FROM_EMAIL", default: "no-reply@localhost")
      options
    end

    def twilio_options
      options = ActiveSupport::OrderedOptions.new
      options.enabled = string("TWILIO_ACCOUNT_SID").present?
      options.account_sid = string("TWILIO_ACCOUNT_SID")
      options.auth_token = string("TWILIO_AUTH_TOKEN")
      options.from_number = string("TWILIO_FROM_NUMBER")
      options
    end

    def whatsapp_options
      options = ActiveSupport::OrderedOptions.new
      options.enabled = string("WHATSAPP_ACCESS_TOKEN").present?
      options.access_token = string("WHATSAPP_ACCESS_TOKEN")
      options.phone_number_id = string("WHATSAPP_PHONE_NUMBER_ID")
      options.api_version = string("WHATSAPP_API_VERSION", default: "v20.0")
      options
    end

    def sentry_options
      options = ActiveSupport::OrderedOptions.new
      options.enabled = string("SENTRY_DSN").present?
      options.dsn = string("SENTRY_DSN")
      options.environment = string("SENTRY_ENVIRONMENT", default: Rails.env)
      options.traces_sample_rate = string("SENTRY_TRACES_SAMPLE_RATE", default: "0.0").to_f
      options
    end

    def validate_integrations!
      return unless Rails.env.production?

      required_by_integration.each do |enabled, required_keys|
        require_when_enabled!(enabled, required_keys)
      end
    end

    def apply_app_endpoint!(config)
      config.x.app_host = require_in_production!("APP_HOST") || "api.prescsign.local"
      config.x.app_port = string("APP_PORT", default: "3000").to_i
      config.x.app_protocol = string(
        "APP_PROTOCOL",
        default: Rails.env.production? ? "https" : "http"
      )
    end

    def jwt_secret_key
      return require!("JWT_SECRET_KEY") if Rails.env.production?

      string("JWT_SECRET_KEY", default: "dev-only-change-me")
    end

    # rubocop:disable Metrics/AbcSize
    def required_by_integration
      {
        Rails.application.config.x.object_storage.enabled =>
          %w[S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY S3_REGION],
        Rails.application.config.x.sendgrid.enabled => %w[SENDGRID_FROM_EMAIL],
        Rails.application.config.x.twilio.enabled => %w[TWILIO_AUTH_TOKEN TWILIO_FROM_NUMBER],
        Rails.application.config.x.whatsapp.enabled => %w[WHATSAPP_PHONE_NUMBER_ID]
      }
    end
    # rubocop:enable Metrics/AbcSize

    def require_when_enabled!(enabled, required_keys)
      return unless enabled

      required_keys.each { |key| require!(key) }
    end
  end
  # rubocop:enable Metrics/ModuleLength
end

Rails.application.configure do
  Prescsign::AppConfig.apply!(config)
end
