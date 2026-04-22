require "rails_helper"
require "securerandom"

RSpec.describe OrganizationResponsible, type: :model do
  it "belongs to an organization" do
    responsible = described_class.new

    expect(responsible).not_to be_valid
    expect(responsible.errors[:organization]).to be_present
  end

  it "is valid when organization is present" do
    organization = Organization.create!(
      name: "Organizacao Resp #{SecureRandom.hex(4)}",
      kind: "autonomo"
    )

    responsible = described_class.new(organization: organization)

    expect(responsible).to be_valid
  end

  it "supports external responsible without user link" do
    organization = Organization.create!(
      name: "Organizacao Externa #{SecureRandom.hex(4)}",
      kind: "autonomo"
    )

    responsible = described_class.new(organization: organization, user: nil)

    expect(responsible).to be_valid
  end

  it "supports external responsible linked to user" do
    organization = Organization.create!(
      name: "Organizacao User Externo #{SecureRandom.hex(4)}",
      kind: "autonomo"
    )
    user = create_user

    responsible = described_class.new(organization: organization, user: user)

    expect(responsible).to be_valid
    expect(responsible.user).to eq(user)
  end

  it "supports internal responsible linked to a user account" do
    organization = Organization.create!(
      name: "Organizacao User Interno #{SecureRandom.hex(4)}",
      kind: "autonomo"
    )
    doctor_user = create_confirmed_doctor

    responsible = described_class.new(organization: organization, user: doctor_user)

    expect(responsible).to be_valid
    expect(responsible.user).to eq(doctor_user)
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr Responsible #{suffix}",
      email: "org.responsible.#{suffix}@example.com",
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
      email: "org.user.responsible.#{suffix}@example.com",
      encrypted_password: "encrypted-token",
      status: "active"
    )
  end
end
