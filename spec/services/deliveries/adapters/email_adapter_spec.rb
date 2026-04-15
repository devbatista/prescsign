require "rails_helper"
require "securerandom"

RSpec.describe Deliveries::Adapters::EmailAdapter do
  it "dispatches using mailer and returns normalized response" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document(doctor:, patient:)

    mail = instance_double(Mail::Message, message_id: "<msg-123@example.com>")
    message_delivery = double("message_delivery", deliver_now: mail)
    mailer_scope = double("mailer_scope", notify_document: message_delivery)

    allow(DocumentDeliveryMailer).to receive(:with).and_return(mailer_scope)

    result = described_class.new(
      document: document,
      recipient: patient.email
    ).call

    expect(result[:status]).to eq("sent")
    expect(result[:provider_name]).to eq("action_mailer")
    expect(result[:provider_message_id]).to eq("<msg-123@example.com>")
    expect(result[:metadata]).to include(channel: "email")
  end

  private

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dra Email #{suffix}",
      email: "email.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end

  def create_patient(doctor:)
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    Patient.create!(
      doctor: doctor,
      full_name: "Paciente Email #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1),
      email: "paciente.email.#{suffix}@example.com"
    )
  end

  def create_document(doctor:, patient:)
    prescription = Prescription.create!(
      doctor: doctor,
      patient: patient,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Conteudo inicial",
      issued_on: Date.current,
      status: "draft"
    )

    Document.create!(
      doctor: doctor,
      patient: patient,
      documentable: prescription,
      kind: "prescription",
      code: SecureRandom.alphanumeric(10).upcase,
      status: "issued",
      issued_on: Date.current,
      current_version: 1
    )
  end
end
