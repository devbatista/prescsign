require "rails_helper"
require "securerandom"

RSpec.describe LegacyDoctorUserMapping, type: :model do
  it "is valid with legacy doctor, user and backfilled_at" do
    doctor = create_confirmed_doctor
    user = create_user

    mapping = described_class.new(
      legacy_doctor: doctor,
      user: user,
      backfilled_at: Time.current
    )

    expect(mapping).to be_valid
  end

  it "requires backfilled_at" do
    doctor = create_confirmed_doctor
    user = create_user

    mapping = described_class.new(legacy_doctor: doctor, user: user, backfilled_at: nil)

    expect(mapping).not_to be_valid
    expect(mapping.errors[:backfilled_at]).to be_present
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr Mapping #{suffix}",
      email: "mapping.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end

  def create_user
    suffix = SecureRandom.hex(4)
    User.create!(
      email: "mapping.user.#{suffix}@example.com",
      encrypted_password: "encrypted-token",
      status: "active"
    )
  end
end
