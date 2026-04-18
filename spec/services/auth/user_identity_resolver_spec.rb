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
    user = User.create!(email: doctor.email, encrypted_password: "encrypted", status: "active")

    resolved = described_class.resolve_for_doctor(doctor)

    expect(resolved.id).to eq(user.id)
    expect(LegacyDoctorUserMapping.find_by(legacy_doctor_id: doctor.id, user_id: user.id)).to be_present
  end

  it "returns nil when provisioning fallback is disabled and no identity exists" do
    doctor = create_confirmed_doctor

    resolved = described_class.resolve_for_doctor(doctor, allow_provisioning: false)

    expect(resolved).to be_nil
    expect(LegacyDoctorUserMapping.find_by(legacy_doctor_id: doctor.id)).to be_nil
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
