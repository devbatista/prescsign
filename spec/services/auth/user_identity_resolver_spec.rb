require "rails_helper"
require "securerandom"

RSpec.describe Auth::UserIdentityResolver do
  it "provisions and links user identity for doctor when missing mapping" do
    doctor = create_confirmed_doctor

    user = described_class.resolve_for_doctor(doctor)

    expect(user).to be_present
    expect(user.email).to eq(doctor.email.downcase)
    expect(user.user_roles.where(role: "doctor", status: "active")).to exist
    expect(user.doctor_profile).to be_present
    expect(user.doctor_profile.doctor_id).to eq(doctor.id)
    expect(LegacyDoctorUserMapping.find_by(legacy_doctor_id: doctor.id, user_id: user.id)).to be_present
  end

  it "links existing user by email when mapping is missing" do
    doctor = create_confirmed_doctor
    user = User.find_by!(email: doctor.email.downcase)
    LegacyDoctorUserMapping.where(legacy_doctor_id: doctor.id).delete_all
    doctor.doctor_profile&.destroy!
    doctor.reload

    resolved = described_class.resolve_for_doctor(doctor)

    expect(resolved.id).to eq(user.id)
    expect(LegacyDoctorUserMapping.find_by(legacy_doctor_id: doctor.id, user_id: user.id)).to be_present
  end

  it "returns nil when provisioning fallback is disabled and no identity exists" do
    doctor = Doctor.new(
      full_name: "Dr No Identity",
      email: "no.identity.#{SecureRandom.hex(4)}@example.com",
      cpf: "12345123456",
      license_number: "CRM0001",
      license_state: "SP"
    )

    resolved = described_class.resolve_for_doctor(doctor, allow_provisioning: false)

    expect(resolved).to be_nil
    expect(LegacyDoctorUserMapping.find_by(legacy_doctor_id: doctor.id)).to be_nil
  end

  it "respects users migration rollout fallback flag" do
    original = Rails.application.config.x.users_migration.allow_doctor_fallback
    Rails.application.config.x.users_migration.allow_doctor_fallback = false

    expect(described_class.fallback_provisioning_enabled?).to be(false)
  ensure
    Rails.application.config.x.users_migration.allow_doctor_fallback = original
  end

  it "does not provision identity when users are required" do
    doctor = Doctor.new(
      full_name: "Dr Required Identity",
      email: "required.identity.#{SecureRandom.hex(4)}@example.com",
      cpf: "12345123456",
      license_number: "CRM0002",
      license_state: "SP"
    )
    original_required = Rails.application.config.x.auth.users_required
    original_phase = Rails.application.config.x.users_migration.phase
    Rails.application.config.x.auth.users_required = true
    Rails.application.config.x.users_migration.phase = "phase3_users_required"

    resolved = described_class.resolve_for_doctor(doctor, allow_provisioning: true)

    expect(resolved).to be_nil
  ensure
    Rails.application.config.x.auth.users_required = original_required
    Rails.application.config.x.users_migration.phase = original_phase
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr Resolver #{suffix}",
      email: "resolver.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end
end
