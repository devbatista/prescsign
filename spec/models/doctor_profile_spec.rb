require "rails_helper"
require "securerandom"

RSpec.describe DoctorProfile, type: :model do
  it "requires user and medical license fields" do
    profile = described_class.new

    expect(profile).not_to be_valid
    expect(profile.errors[:user]).to be_present
    expect(profile.errors[:license_number]).to be_present
    expect(profile.errors[:license_state]).to be_present
  end

  it "normalizes cpf and license identifiers" do
    profile = described_class.new(
      user: create_user,
      cpf: "123.456.789-10",
      license_number: " crm123 ",
      license_state: "sp"
    )
    profile.validate

    expect(profile.cpf).to eq("12345678910")
    expect(profile.license_number).to eq("CRM123")
    expect(profile.license_state).to eq("SP")
  end

  def create_user
    suffix = SecureRandom.hex(4)
    User.create!(
      email: "doctor.profile.#{suffix}@example.com",
      encrypted_password: "encrypted-token",
      status: "active"
    )
  end
end
