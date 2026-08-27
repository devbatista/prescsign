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
      config.x.auth = auth_options
      config.x.users_migration = users_migration_options
      config.x.observability = observability_options
      config.x.signature_provider = string("SIGNATURE_PROVIDER", default: "internal")
      config.x.icp_brasil_provider = icp_brasil_provider_options
      config.x.eval_crypto_cubo_provider = eval_crypto_cubo_provider_options
      config.x.sncr = sncr_options
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
      config.x.smtp = smtp_options
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

    # Entrega de e-mail por SMTP (AWS SES em produção). `enabled` espelha o que
    # production.rb usa para decidir entre :smtp e o default do Rails.
    def smtp_options
      options = ActiveSupport::OrderedOptions.new
      options.enabled = string("SMTP_ADDRESS").present?
      options.address = string("SMTP_ADDRESS")
      options.port = string("SMTP_PORT", default: "587").to_i
      options.user_name = string("SMTP_USER_NAME")
      options.password = string("SMTP_PASSWORD")
      options.domain = string("SMTP_DOMAIN")
      options.authentication = string("SMTP_AUTHENTICATION", default: "login")
      options.enable_starttls_auto = string("SMTP_ENABLE_STARTTLS_AUTO", default: "true") == "true"
      options.from_email = string("SMTP_FROM_EMAIL", default: "no-reply@localhost")
      # Nome exibido no From:. O endereço é sempre o do domínio verificado no
      # SES; só este rótulo varia por contexto (ver Mailers::SenderAddress).
      options.from_name = string("SMTP_FROM_NAME", default: "PrescSign")
      options
    end

    # Twilio é o provedor do canal WhatsApp (Sandbox nos ambientes de teste,
    # número próprio em produção). `whatsapp_from` é o número remetente em
    # E.164 — o prefixo de canal `whatsapp:` é responsabilidade do adapter.
    # O timeout fica abaixo do `DELIVERIES_TIMEOUT_SECONDS` de propósito: assim
    # o erro que chega ao job é o do HTTP, já classificável, e não o timeout
    # genérico do dispatcher.
    def twilio_options
      options = ActiveSupport::OrderedOptions.new
      options.enabled = string("TWILIO_ACCOUNT_SID").present?
      options.account_sid = string("TWILIO_ACCOUNT_SID")
      options.auth_token = string("TWILIO_AUTH_TOKEN")
      options.whatsapp_from = string("TWILIO_WHATSAPP_FROM")
      options.base_url = string("TWILIO_BASE_URL", default: "https://api.twilio.com")
      options.timeout_seconds = string("TWILIO_TIMEOUT_SECONDS", default: "8").to_i
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

    def icp_brasil_provider_options
      options = ActiveSupport::OrderedOptions.new
      options.base_url = string("ICP_BRASIL_PROVIDER_BASE_URL")
      options.api_key = string("ICP_BRASIL_PROVIDER_API_KEY")
      options.timeout_seconds = string("ICP_BRASIL_PROVIDER_TIMEOUT_SECONDS", default: "30").to_i
      options
    end

    def eval_crypto_cubo_provider_options
      options = ActiveSupport::OrderedOptions.new
      options.base_url = string("EVAL_CRYPTO_CUBO_BASE_URL")
      options.api_key = string("EVAL_CRYPTO_CUBO_API_KEY")
      options.operator_id = string("EVAL_CRYPTO_CUBO_OPERATOR_ID")
      options.type = string("EVAL_CRYPTO_CUBO_TYPE")
      options.format = string("EVAL_CRYPTO_CUBO_FORMAT", default: "detached")
      options.profile = string("EVAL_CRYPTO_CUBO_PROFILE")
      options.icpbr = string("EVAL_CRYPTO_CUBO_ICPBR", default: "false")
      options.alias_name = string("EVAL_CRYPTO_CUBO_ALIAS")
      # Força o alias/CPF do .env (certificado fixo de local/homologação) em vez
      # do CPF do médico logado.
      options.use_config_alias = string("EVAL_CRYPTO_CUBO_USE_CONFIG_ALIAS", default: "false")
      options.pin = string("EVAL_CRYPTO_CUBO_PIN")
      options.timeout_seconds = string("EVAL_CRYPTO_CUBO_TIMEOUT_SECONDS", default: "30").to_i
      options
    end

    def sncr_options
      options = ActiveSupport::OrderedOptions.new
      options.enabled = string("SNCR_ENABLED", default: "false") == "true"
      options.base_url = string("SNCR_BASE_URL", default: "https://sncr-api.hmg.apps.anvisa.gov.br/api/v1")
      options.timeout_seconds = string("SNCR_TIMEOUT_SECONDS", default: "30").to_i
      options.auth_callback_url = string("SNCR_AUTH_CALLBACK_URL")
      options.platform_cnpj = string("SNCR_PLATFORM_CNPJ")
      # Modo simulado (Sncr::FakeClient): gera numeração local, sem Gov.br nem
      # CPF de prescritor cadastrado no SNCR. Nunca vale em produção — numeração
      # inventada em receita real de controlado é falsificação de documento
      # sanitário —, mesmo que a variável vaze para o ambiente.
      options.fake = !Rails.env.production? && string("SNCR_FAKE", default: "false") == "true"
      options
    end

    def auth_options
      options = ActiveSupport::OrderedOptions.new
      options.users_required = string("AUTH_USERS_REQUIRED", default: "false") == "true"
      options.users_fallback_provisioning = string("AUTH_USERS_FALLBACK_PROVISIONING", default: "true") == "true"
      options
    end

    def users_migration_options
      options = ActiveSupport::OrderedOptions.new
      options.phase = string("USERS_MIGRATION_PHASE", default: "phase2_users_auth_enabled")
      options.allow_doctor_fallback = string("USERS_MIGRATION_ALLOW_DOCTOR_FALLBACK", default: "true") == "true"
      options
    end

    def observability_options
      options = ActiveSupport::OrderedOptions.new
      options.slow_request_threshold_ms = string("OBS_SLOW_REQUEST_THRESHOLD_MS", default: "1200").to_i
      options.rollout_phase = string("OBS_ROLLOUT_PHASE", default: "users_migration")
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

    # rubocop:disable Metrics/AbcSize
    def required_by_integration
      {
        Rails.application.config.x.object_storage.enabled =>
          %w[S3_ACCESS_KEY_ID S3_SECRET_ACCESS_KEY S3_REGION],
        Rails.application.config.x.smtp.enabled =>
          %w[SMTP_USER_NAME SMTP_PASSWORD SMTP_FROM_EMAIL],
        Rails.application.config.x.twilio.enabled => %w[TWILIO_AUTH_TOKEN TWILIO_WHATSAPP_FROM],
        Rails.application.config.x.whatsapp.enabled => %w[WHATSAPP_PHONE_NUMBER_ID],
        Rails.application.config.x.signature_provider == "icp_brasil" =>
          %w[ICP_BRASIL_PROVIDER_BASE_URL ICP_BRASIL_PROVIDER_API_KEY],
        Rails.application.config.x.signature_provider == "eval_crypto_cubo" =>
          %w[
            EVAL_CRYPTO_CUBO_BASE_URL
            EVAL_CRYPTO_CUBO_API_KEY
            EVAL_CRYPTO_CUBO_PROFILE
            EVAL_CRYPTO_CUBO_ALIAS
            EVAL_CRYPTO_CUBO_PIN
          ],
        Rails.application.config.x.sncr.enabled =>
          %w[
            SNCR_BASE_URL
            SNCR_AUTH_CALLBACK_URL
            SNCR_PLATFORM_CNPJ
          ]
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
