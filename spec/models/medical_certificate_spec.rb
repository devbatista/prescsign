require "rails_helper"
require "securerandom"

RSpec.describe MedicalCertificate, type: :model do
  it "rejects rest_end_on before rest_start_on" do
    doctor = build_doctor
    patient = build_patient(doctor: doctor)

    certificate = described_class.new(
      doctor: doctor,
      patient: patient,
      organization: patient.organization,
      code: unique_code,
      content: "Afastamento por sintomas gripais",
      issued_on: Date.current,
      rest_start_on: Date.current,
      rest_end_on: Date.yesterday,
      status: "draft"
    )

    expect(certificate).not_to be_valid
    expect(certificate.errors[:rest_end_on]).to be_present
  end

  it "assigns organization from patient when missing" do
    doctor = build_doctor
    patient = build_patient(doctor: doctor)

    certificate = described_class.new(
      doctor: doctor,
      patient: patient,
      code: unique_code,
      content: "Repouso por 2 dias",
      issued_on: Date.current,
      rest_start_on: Date.current,
      rest_end_on: Date.current + 1.day,
      status: "draft"
    )

    certificate.validate

    expect(certificate.organization_id).to eq(patient.organization_id)
  end

  it "rejects organization outside doctor/patient context" do
    doctor = build_doctor
    patient = build_patient(doctor: doctor)
    foreign_organization = Organization.create!(name: "Hospital Fora", kind: "hospital", legal_name: "Hospital Fora SA", cnpj: unique_cnpj)

    certificate = described_class.new(
      doctor: doctor,
      patient: patient,
      organization: foreign_organization,
      code: unique_code,
      content: "Afastamento",
      issued_on: Date.current,
      rest_start_on: Date.current,
      rest_end_on: Date.current + 2.days,
      status: "draft"
    )

    expect(certificate).not_to be_valid
    expect(certificate.errors[:organization_id]).to include("must match patient and user organization context")
  end

  def build_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr Certificate #{suffix}",
      email: "dr.certificate.#{suffix}@example.com",
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
      full_name: "Paciente Atestado",
      cpf: unique_cpf,
      birth_date: Date.new(1988, 1, 1)
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
