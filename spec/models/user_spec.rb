require "rails_helper"
require "securerandom"

RSpec.describe User, type: :model do
  it "normalizes email and status" do
    user = described_class.new(
      email: "  USER.TEST@EXAMPLE.COM ",
      encrypted_password: "encrypted-token",
      status: "  ACTIVE "
    )

    user.validate

    expect(user.email).to eq("user.test@example.com")
    expect(user.status).to eq("active")
  end

  it "enforces case-insensitive unique email" do
    described_class.create!(
      email: "duplicate@example.com",
      encrypted_password: "encrypted-token",
      status: "active"
    )

    user = described_class.new(
      email: "DUPLICATE@EXAMPLE.COM",
      encrypted_password: "encrypted-token",
      status: "active"
    )

    expect(user).not_to be_valid
    expect(user.errors[:email]).to include("has already been taken")
  end

  it "resolves doctor context and organization from doctor_profile" do
    doctor = create_confirmed_doctor
    user = doctor.user || described_class.create!(
      email: "linked.#{SecureRandom.hex(4)}@example.com",
      encrypted_password: "encrypted-token",
      status: "active"
    )
    DoctorProfile.find_or_create_by!(user: user) do |profile|
      profile.doctor = doctor
      profile.cpf = doctor.cpf
      profile.license_number = doctor.license_number
      profile.license_state = doctor.license_state
      profile.specialty = doctor.specialty
    end

    expect(user.doctor_id).to eq(doctor.id)
    expect(user.current_organization_id).to eq(doctor.current_organization_id)
    expect(user.membership_for(doctor.current_organization_id)).to be_present
  end

  it "evaluates admin by active roles" do
    user = described_class.create!(
      email: "admin.#{SecureRandom.hex(4)}@example.com",
      encrypted_password: "encrypted-token",
      status: "active"
    )
    user.user_roles.create!(role: "admin", status: "active")

    expect(user.admin?).to be(true)
    expect(user.organization_admin?).to be(true)
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr User Model #{suffix}",
      email: "user.model.#{suffix}@example.com",
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
