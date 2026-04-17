require "rails_helper"
require "securerandom"

RSpec.describe DeliveryLog, type: :model do
  it "requires error_message when status is failed" do
    log = described_class.new(
      channel: "email",
      status: "failed",
      attempted_at: Time.current,
      recipient: "patient@example.com"
    )

    expect(log).not_to be_valid
    expect(log.errors[:error_message]).to include("can't be blank")
  end

  it "requires delivered_at when status is delivered" do
    log = described_class.new(
      channel: "email",
      status: "delivered",
      attempted_at: Time.current,
      recipient: "patient@example.com"
    )

    expect(log).not_to be_valid
    expect(log.errors[:delivered_at]).to include("can't be blank")
  end

  it "assigns organization from document when missing" do
    doctor = build_doctor
    patient = build_patient(doctor: doctor)
    prescription = build_prescription(doctor: doctor, patient: patient)
    document = build_document(doctor: doctor, patient: patient, prescription: prescription)

    log = described_class.new(
      doctor: doctor,
      patient: patient,
      document: document,
      channel: "email",
      status: "sent",
      attempted_at: Time.current,
      recipient: "patient@example.com"
    )

    log.validate

    expect(log.organization_id).to eq(document.organization_id)
  end

  def build_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr Delivery #{suffix}",
      email: "dr.delivery.#{suffix}@example.com",
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
      full_name: "Paciente Entrega",
      cpf: unique_cpf,
      birth_date: Date.new(1986, 1, 1)
    )
  end

  def build_prescription(doctor:, patient:)
    Prescription.create!(
      doctor: doctor,
      patient: patient,
      organization: patient.organization,
      code: unique_code,
      content: "Conteudo de entrega",
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
