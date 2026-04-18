module Prescsign
  module AppConfig
    MIN_LOG_RETENTION_DAYS = 1825
    PERMANENT_RETENTION_TOKENS = %w[permanent forever infinite].freeze

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
      apply_retention!(config)
      apply_integrations!(config)
      validate_integrations!
      validate_retention!
    end

    def apply_core!(config)
      apply_app_endpoint!(config)
      config.x.redis_url = string("REDIS_URL", default: "redis://localhost:6379/1")
      config.x.jwt_secret_key = jwt_secret_key
      config.x.cors = cors_options
      config.x.auth = auth_options
      config.x.documents_pdf_signed_url_expires_in = string("DOCUMENTS_PDF_SIGNED_URL_EXPIRES_IN", default: "900").to_i
      config.x.pdf_generation_timeout_seconds = string("PDF_GENERATION_TIMEOUT_SECONDS", default: "20").to_i
    end

    def apply_retention!(config)
      options = ActiveSupport::OrderedOptions.new
      options.document_versions_days = document_versions_retention_days
      options.documents_permanent = options.document_versions_days.nil?
      options.audit_logs_days = retention_days("RETENTION_AUDIT_LOGS_DAYS", default: "2190")
      options.delivery_logs_days = retention_days("RETENTION_DELIVERY_LOGS_DAYS", default: MIN_LOG_RETENTION_DAYS.to_s)
      options.tmp_files_days = retention_days("RETENTION_TMP_FILES_DAYS", default: "7")
      options.unattached_blobs_days = retention_days("RETENTION_UNATTACHED_BLOBS_DAYS", default: "2")
      config.x.retention = options
    end

    def apply_integrations!(config)
      config.x.object_storage = object_storage_options
      config.x.sendgrid = sendgrid_options
      config.x.twilio = twilio_options
      config.x.whatsapp = whatsapp_options
      config.x.deliveries = deliveries_options
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
      options.timeout_seconds = string("SENTRY_TIMEOUT_SECONDS", default: "2").to_i
      options
    end

    def deliveries_options
      options = ActiveSupport::OrderedOptions.new
      options.timeout_seconds = string("DELIVERIES_TIMEOUT_SECONDS", default: "10").to_i
      options
    end

    def cors_options
      options = ActiveSupport::OrderedOptions.new
      defaults = "http://localhost:5173,http://127.0.0.1:5173"
      raw_origins = string("CORS_ALLOWED_ORIGINS", default: defaults)
      options.allowed_origins = raw_origins.to_s.split(",").map(&:strip).reject(&:blank?)
      options
    end

    def auth_options
      options = ActiveSupport::OrderedOptions.new
      options.users_required = string("AUTH_USERS_REQUIRED", default: "false") == "true"
      options.users_fallback_provisioning = string("AUTH_USERS_FALLBACK_PROVISIONING", default: "true") == "true"
      options
    end

    def validate_integrations!
      return unless Rails.env.production?

      required_by_integration.each do |enabled, required_keys|
        require_when_enabled!(enabled, required_keys)
      end
    end

    def validate_retention!
      return unless Rails.env.production?

      retention = Rails.application.config.x.retention
      unless retention.documents_permanent
        raise ArgumentError, "RETENTION_DOCUMENT_VERSIONS_DAYS must be 'permanent' in production"
      end

      if retention.audit_logs_days < MIN_LOG_RETENTION_DAYS
        raise ArgumentError, "RETENTION_AUDIT_LOGS_DAYS must be at least #{MIN_LOG_RETENTION_DAYS} days in production"
      end

      if retention.delivery_logs_days < MIN_LOG_RETENTION_DAYS
        raise ArgumentError, "RETENTION_DELIVERY_LOGS_DAYS must be at least #{MIN_LOG_RETENTION_DAYS} days in production"
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
        Rails.application.config.x.whatsapp.enabled => %w[WHATSAPP_PHONE_NUMBER_ID],
        Rails.application.config.x.cors.allowed_origins.blank? => %w[CORS_ALLOWED_ORIGINS]
      }
    end
    # rubocop:enable Metrics/AbcSize

    def require_when_enabled!(enabled, required_keys)
      return unless enabled

      required_keys.each { |key| require!(key) }
    end

    def document_versions_retention_days
      raw_value = string("RETENTION_DOCUMENT_VERSIONS_DAYS", default: "permanent").to_s.strip.downcase
      return nil if raw_value.blank? || PERMANENT_RETENTION_TOKENS.include?(raw_value)

      Integer(raw_value, 10)
    rescue ArgumentError
      raise ArgumentError, "RETENTION_DOCUMENT_VERSIONS_DAYS must be an integer number of days or 'permanent'"
    end

    def retention_days(key, default:)
      raw_value = string(key, default: default).to_s.strip
      Integer(raw_value, 10)
    rescue ArgumentError
      raise ArgumentError, "#{key} must be an integer number of days"
    end
  end
  # rubocop:enable Metrics/ModuleLength
end

Rails.application.configure do
  Prescsign::AppConfig.apply!(config)
end
