require "rails_helper"
require "securerandom"

RSpec.describe AuditLog, type: :model do
  it "assigns organization and unit from document by default" do
    doctor = build_doctor
    patient = build_patient(doctor: doctor)
    prescription = build_prescription(doctor: doctor, patient: patient)
    document = build_document(doctor: doctor, patient: patient, prescription: prescription)

    log = described_class.new(
      actor: doctor,
      patient: patient,
      document: document,
      resource: document,
      action: "created",
      occurred_at: Time.current
    )

    log.validate

    expect(log.organization_id).to eq(document.organization_id)
    expect(log.unit_id).to eq(document.unit_id)
  end

  it "normalizes action before validation" do
    doctor = build_doctor
    patient = build_patient(doctor: doctor)
    prescription = build_prescription(doctor: doctor, patient: patient)
    document = build_document(doctor: doctor, patient: patient, prescription: prescription)

    log = described_class.new(
      actor: doctor,
      patient: patient,
      document: document,
      resource: document,
      action: "  SIGNED  ",
      occurred_at: Time.current
    )

    log.validate

    expect(log.action).to eq("signed")
  end

  def build_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr Audit #{suffix}",
      email: "dr.audit.#{suffix}@example.com",
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
      full_name: "Paciente Auditoria",
      cpf: unique_cpf,
      birth_date: Date.new(1987, 1, 1)
    )
  end

  def build_prescription(doctor:, patient:)
    Prescription.create!(
      doctor: doctor,
      patient: patient,
      organization: patient.organization,
      code: unique_code,
      content: "Conteudo base",
      issued_on: Date.current,
      status: "draft"
    )
  end

  def build_document(doctor:, patient:, prescription:)
    Document.create!(
      doctor: doctor,
      patient: patient,
      organization: patient.organization,
      unit: patient.organization.default_unit,
      documentable: prescription,
      kind: "prescription",
      code: unique_code,
      status: "issued",
      issued_on: Date.current,
      current_version: 1
    )
  end

  def unique_code
    SecureRandom.alphanumeric(10).upcase
  end

  def unique_cpf
    SecureRandom.random_number(10**11).to_s.rjust(11, "0")
  end
end
