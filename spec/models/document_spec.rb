require "rails_helper"
require "securerandom"

RSpec.describe Document, type: :model do
  it "assigns organization and unit by default from patient/organization context" do
    doctor = build_doctor
    patient = build_patient(doctor: doctor)
    prescription = build_prescription(doctor: doctor, patient: patient)

    document = described_class.new(
      doctor: doctor,
      patient: patient,
      documentable: prescription,
      documentable_type: "Prescription",
      kind: "prescription",
      code: unique_code,
      status: "issued",
      issued_on: Date.current,
      current_version: 1
    )

    document.validate

    expect(document.organization_id).to eq(patient.organization_id)
    expect(document.unit_id).to eq(patient.organization.default_unit.id)
  end

  it "rejects document when kind and documentable_type do not match" do
    doctor = build_doctor
    patient = build_patient(doctor: doctor)
    prescription = build_prescription(doctor: doctor, patient: patient)

    document = described_class.new(
      doctor: doctor,
      patient: patient,
      organization: patient.organization,
      unit: patient.organization.default_unit,
      documentable: prescription,
      documentable_type: "Prescription",
      kind: "medical_certificate",
      code: unique_code,
      status: "issued",
      issued_on: Date.current,
      current_version: 1
    )

    expect(document).not_to be_valid
    expect(document.errors[:documentable_type]).to include("must match document kind")
  end

  it "rejects unit from a different organization" do
    doctor = build_doctor
    patient = build_patient(doctor: doctor)
    prescription = build_prescription(doctor: doctor, patient: patient)
    foreign_organization = Organization.create!(name: "Hospital Z", kind: "hospital", legal_name: "Hospital Z SA", cnpj: unique_cnpj)

    document = described_class.new(
      doctor: doctor,
      patient: patient,
      organization: patient.organization,
      unit: foreign_organization.default_unit,
      documentable: prescription,
      documentable_type: "Prescription",
      kind: "prescription",
      code: unique_code,
      status: "issued",
      issued_on: Date.current,
      current_version: 1
    )

    expect(document).not_to be_valid
    expect(document.errors[:unit_id]).to include("must belong to the same organization")
  end

  def build_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr Document #{suffix}",
      email: "dr.document.#{suffix}@example.com",
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
      full_name: "Paciente Documento",
      cpf: unique_cpf,
      birth_date: Date.new(1990, 1, 1),
      email: "paciente.documento.#{SecureRandom.hex(2)}@example.com"
    )
  end

  def build_prescription(doctor:, patient:)
    Prescription.create!(
      doctor: doctor,
      patient: patient,
      organization: patient.organization,
      code: unique_code,
      content: "Tomar medicacao por 7 dias",
      issued_on: Date.current,
      status: "draft"
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
