require "rails_helper"
require "securerandom"

RSpec.describe Patient, type: :model do
  it "assigns default organization from doctor's current organization" do
    doctor = build_doctor
    patient = described_class.new(
      doctor: doctor,
      full_name: "Paciente Default",
      cpf: unique_cpf,
      birth_date: Date.new(1990, 1, 1)
    )

    patient.validate

    expect(patient.organization_id).to eq(doctor.current_organization_id)
  end

  it "rejects organization outside doctor's memberships" do
    doctor = build_doctor
    foreign_organization = Organization.create!(name: "Clinica Externa", kind: "clinica", legal_name: "Clinica Externa LTDA", cnpj: unique_cnpj)

    patient = described_class.new(
      doctor: doctor,
      organization: foreign_organization,
      full_name: "Paciente Invalido",
      cpf: unique_cpf,
      birth_date: Date.new(1991, 1, 1)
    )

    expect(patient).not_to be_valid
    expect(patient.errors[:organization_id]).to include("must belong to one of user's organizations")
  end

  it "allows same cpf in different organizations" do
    doctor = build_doctor
    shared_cpf = unique_cpf

    described_class.create!(
      doctor: doctor,
      organization: doctor.current_organization,
      full_name: "Paciente Org A",
      cpf: shared_cpf,
      birth_date: Date.new(1992, 1, 1)
    )

    other_organization = Organization.create!(name: "Clinica B", kind: "clinica", legal_name: "Clinica B LTDA", cnpj: unique_cnpj)
    doctor.organization_memberships.create!(organization: other_organization, role: "doctor", status: "active")

    patient = described_class.new(
      doctor: doctor,
      organization: other_organization,
      full_name: "Paciente Org B",
      cpf: shared_cpf,
      birth_date: Date.new(1993, 1, 1)
    )

    expect(patient).to be_valid
  end

  it "rejects duplicate email within the same organization" do
    doctor = build_doctor
    shared_email = "paciente@email.com"

    described_class.create!(
      doctor: doctor,
      organization: doctor.current_organization,
      full_name: "Paciente Email A",
      cpf: unique_cpf,
      birth_date: Date.new(1992, 1, 1),
      email: shared_email
    )

    patient = described_class.new(
      doctor: doctor,
      organization: doctor.current_organization,
      full_name: "Paciente Email B",
      cpf: unique_cpf,
      birth_date: Date.new(1993, 1, 1),
      email: shared_email
    )

    expect(patient).not_to be_valid
    expect(patient.errors[:email]).to include("has already been taken")
  end

  it "allows same email in different organizations" do
    doctor = build_doctor
    shared_email = "paciente@multi-org.com"

    described_class.create!(
      doctor: doctor,
      organization: doctor.current_organization,
      full_name: "Paciente Email Org A",
      cpf: unique_cpf,
      birth_date: Date.new(1992, 1, 1),
      email: shared_email
    )

    other_organization = Organization.create!(name: "Clinica C", kind: "clinica", legal_name: "Clinica C LTDA", cnpj: unique_cnpj)
    doctor.organization_memberships.create!(organization: other_organization, role: "doctor", status: "active")

    patient = described_class.new(
      doctor: doctor,
      organization: other_organization,
      full_name: "Paciente Email Org B",
      cpf: unique_cpf,
      birth_date: Date.new(1993, 1, 1),
      email: shared_email
    )

    expect(patient).to be_valid
  end

  def build_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr Patient #{suffix}",
      email: "dr.patient.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end

  def unique_cpf
    SecureRandom.random_number(10**11).to_s.rjust(11, "0")
  end

  def unique_cnpj
    SecureRandom.random_number(10**14).to_s.rjust(14, "0")
  end
end
