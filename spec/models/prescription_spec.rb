require "rails_helper"
require "securerandom"

RSpec.describe Prescription, type: :model do
  it "assigns organization from patient when not informed" do
    doctor = build_doctor
    patient = build_patient(doctor: doctor)

    prescription = described_class.new(
      doctor: doctor,
      patient: patient,
      code: unique_code,
      content: "Repouso e hidratacao",
      issued_on: Date.current,
      status: "draft"
    )

    prescription.validate

    expect(prescription.organization_id).to eq(patient.organization_id)
  end

  it "rejects valid_until before issued_on" do
    doctor = build_doctor
    patient = build_patient(doctor: doctor)

    prescription = described_class.new(
      doctor: doctor,
      patient: patient,
      organization: patient.organization,
      code: unique_code,
      content: "Uso continuo",
      issued_on: Date.current,
      valid_until: Date.yesterday,
      status: "draft"
    )

    expect(prescription).not_to be_valid
    expect(prescription.errors[:valid_until]).to be_present
  end

  it "rejects organization that does not match doctor/patient context" do
    doctor = build_doctor
    patient = build_patient(doctor: doctor)
    foreign_organization = Organization.create!(name: "Clinica Fora", kind: "clinica", legal_name: "Clinica Fora LTDA", cnpj: unique_cnpj)

    prescription = described_class.new(
      doctor: doctor,
      patient: patient,
      organization: foreign_organization,
      code: unique_code,
      content: "Uso por 10 dias",
      issued_on: Date.current,
      status: "draft"
    )

    expect(prescription).not_to be_valid
    expect(prescription.errors[:organization_id]).to include("must match patient and user organization context")
  end

  def build_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr Prescription #{suffix}",
      email: "dr.prescription.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end

  def build_patient(doctor:)
    Patient.create!(
      doctor: doctor,
      organization: doctor.current_organization,
      full_name: "Paciente Receita",
      cpf: unique_cpf,
      birth_date: Date.new(1989, 1, 1)
    )
  end

  def unique_code
    SecureRandom.alphanumeric(10).upcase
  end

  def unique_cpf
    SecureRandom.random_number(10**11).to_s.rjust(11, "0")
  end

  def unique_cnpj
    SecureRandom.random_number(10**14).to_s.rjust(14, "0")
  end
end
