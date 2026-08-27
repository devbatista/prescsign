require "rails_helper"

RSpec.describe Prescsign::AppConfig do
  describe ".apply_core!" do
    it "loads users migration defaults" do
      with_env(
        "USERS_MIGRATION_PHASE" => nil,
        "USERS_MIGRATION_ALLOW_DOCTOR_FALLBACK" => nil
      ) do
        config = build_config
        described_class.apply_core!(config)

        users_migration = config.x.users_migration
        expect(users_migration.phase).to eq("phase2_users_auth_enabled")
        expect(users_migration.allow_doctor_fallback).to be(true)
      end
    end

    it "parses users migration fallback flag from env" do
      with_env("USERS_MIGRATION_ALLOW_DOCTOR_FALLBACK" => "false") do
        config = build_config
        described_class.apply_core!(config)

        expect(config.x.users_migration.allow_doctor_fallback).to be(false)
      end
    end

    it "loads EVALCryptoCubo provider options" do
      with_env(
        "EVAL_CRYPTO_CUBO_BASE_URL" => "https://api.cryptocubo.example",
        "EVAL_CRYPTO_CUBO_OPERATOR_ID" => "operator-1",
        "EVAL_CRYPTO_CUBO_TYPE" => "qualified",
        "EVAL_CRYPTO_CUBO_FORMAT" => nil,
        "EVAL_CRYPTO_CUBO_PROFILE" => "adrb",
        "EVAL_CRYPTO_CUBO_ICPBR" => nil,
        "EVAL_CRYPTO_CUBO_TIMEOUT_SECONDS" => "45"
      ) do
        config = build_config
        described_class.apply_core!(config)

        provider = config.x.eval_crypto_cubo_provider
        expect(provider.base_url).to eq("https://api.cryptocubo.example")
        expect(provider.operator_id).to eq("operator-1")
        expect(provider.type).to eq("qualified")
        expect(provider.format).to eq("detached")
        expect(provider.profile).to eq("adrb")
        expect(provider.icpbr).to eq("false")
        expect(provider.timeout_seconds).to eq(45)
      end
    end

    it "enables the SNCR fake numbering mode in development" do
      with_env("SNCR_FAKE" => "true") do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
        config = build_config
        described_class.apply_core!(config)

        expect(config.x.sncr.fake).to be(true)
      end
    end

    it "ignores the SNCR fake numbering mode in production" do
      with_env("SNCR_FAKE" => "true") do
        allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
        config = build_config
        described_class.apply_core!(config)

        expect(config.x.sncr.fake).to be(false)
      end
    end

    # O dotenv carrega o mesmo .env na suíte: sem esse corte, o SNCR_FAKE da
    # máquina de quem roda mudaria o resultado dos specs.
    it "ignores the SNCR fake numbering mode in test" do
      with_env("SNCR_FAKE" => "true") do
        config = build_config
        described_class.apply_core!(config)

        expect(config.x.sncr.fake).to be(false)
      end
    end
  end

  describe ".apply_retention!" do
    it "uses permanent document retention and five-year delivery retention by default" do
      with_env(
        "RETENTION_DOCUMENT_VERSIONS_DAYS" => nil,
        "RETENTION_AUDIT_LOGS_DAYS" => nil,
        "RETENTION_DELIVERY_LOGS_DAYS" => nil
      ) do
        config = build_config
        described_class.apply_retention!(config)

        retention = config.x.retention
        expect(retention.document_versions_days).to be_nil
        expect(retention.documents_permanent).to be(true)
        expect(retention.audit_logs_days).to eq(2190)
        expect(retention.delivery_logs_days).to eq(1825)
      end
    end

    it "supports explicit finite retention for document versions outside production checks" do
      with_env("RETENTION_DOCUMENT_VERSIONS_DAYS" => "3650") do
        config = build_config
        described_class.apply_retention!(config)

        retention = config.x.retention
        expect(retention.document_versions_days).to eq(3650)
        expect(retention.documents_permanent).to be(false)
      end
    end
  end

  describe ".validate_retention!" do
    it "rejects non-permanent documents retention in production" do
      with_production_retention(
        documents_permanent: false,
        audit_logs_days: 2190,
        delivery_logs_days: 1825
      ) do
        expect { described_class.validate_retention! }.to raise_error(
          ArgumentError,
          /RETENTION_DOCUMENT_VERSIONS_DAYS must be 'permanent'/
        )
      end
    end

    it "rejects delivery logs retention below minimum in production" do
      with_production_retention(
        documents_permanent: true,
        audit_logs_days: 2190,
        delivery_logs_days: 365
      ) do
        expect { described_class.validate_retention! }.to raise_error(
          ArgumentError,
          /RETENTION_DELIVERY_LOGS_DAYS must be at least/
        )
      end
    end
  end

  private

  def build_config
    config = ActiveSupport::OrderedOptions.new
    config.x = ActiveSupport::OrderedOptions.new
    config
  end

  def with_env(values)
    previous = {}
    values.each do |key, value|
      previous[key] = ENV[key]
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
    yield
  ensure
    previous.each do |key, value|
      value.nil? ? ENV.delete(key) : ENV[key] = value
    end
  end

  def with_production_retention(documents_permanent:, audit_logs_days:, delivery_logs_days:)
    retention = ActiveSupport::OrderedOptions.new
    retention.documents_permanent = documents_permanent
    retention.audit_logs_days = audit_logs_days
    retention.delivery_logs_days = delivery_logs_days

    original_retention = Rails.application.config.x.retention
    Rails.application.config.x.retention = retention
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

    yield
  ensure
    Rails.application.config.x.retention = original_retention
  end
end
