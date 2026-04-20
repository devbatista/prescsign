require "rails_helper"

RSpec.describe Users::MigrationRollout do
  describe ".users_required?" do
    it "returns true when auth users_required is enabled" do
      original_required = Rails.application.config.x.auth.users_required
      Rails.application.config.x.auth.users_required = true

      expect(described_class.users_required?).to be(true)
    ensure
      Rails.application.config.x.auth.users_required = original_required
    end

    it "returns true for required phases" do
      original_phase = Rails.application.config.x.users_migration.phase
      Rails.application.config.x.users_migration.phase = "phase3_users_required"

      expect(described_class.users_required?).to be(true)
    ensure
      Rails.application.config.x.users_migration.phase = original_phase
    end
  end

  describe ".doctor_fallback_allowed?" do
    it "returns false when users are required by phase" do
      original_phase = Rails.application.config.x.users_migration.phase
      original_fallback = Rails.application.config.x.users_migration.allow_doctor_fallback
      original_auth_fallback = Rails.application.config.x.auth.users_fallback_provisioning
      Rails.application.config.x.users_migration.phase = "phase3_users_required"
      Rails.application.config.x.users_migration.allow_doctor_fallback = true
      Rails.application.config.x.auth.users_fallback_provisioning = true

      expect(described_class.doctor_fallback_allowed?).to be(false)
    ensure
      Rails.application.config.x.users_migration.phase = original_phase
      Rails.application.config.x.users_migration.allow_doctor_fallback = original_fallback
      Rails.application.config.x.auth.users_fallback_provisioning = original_auth_fallback
    end
  end
end
