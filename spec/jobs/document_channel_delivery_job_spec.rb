require "rails_helper"
require "securerandom"

RSpec.describe DocumentChannelDeliveryJob, type: :job do
  before do
    ActionMailer::Base.deliveries.clear
  end

  it "creates delivery log and sends document via email channel" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document(doctor:, patient:)

    described_class.perform_now(
      document_id: document.id,
      channel: "email",
      recipient: patient.email,
      request_id: "req-email-1",
      idempotency_key: "doc-#{document.id}-email"
    )

    delivery_log = DeliveryLog.find_by!(idempotency_key: "doc-#{document.id}-email")
    expect(delivery_log.status).to eq("sent")
    expect(delivery_log.channel).to eq("email")
    expect(delivery_log.provider_name).to eq("action_mailer")
    expect(delivery_log.provider_message_id).to be_present
    expect(delivery_log.attempted_at).to be_present
    expect(delivery_log.metadata["attempts"]).to be_present
    expect(delivery_log.metadata["attempts"].last["status"]).to eq("sent")
    expect(delivery_log.metadata["attempts"].last["channel"]).to eq("email")
    expect(delivery_log.metadata["attempts"].last["external_response"]).to include("provider_name")
    expect(delivery_log.metadata["attempts"].last["timestamp"]).to be_present
  end

  it "creates delivery log for sms channel using generic dispatcher" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document(doctor:, patient:)

    described_class.perform_now(
      document_id: document.id,
      channel: "sms",
      recipient: patient.phone,
      request_id: "req-sms-1",
      idempotency_key: "doc-#{document.id}-sms"
    )

    delivery_log = DeliveryLog.find_by!(idempotency_key: "doc-#{document.id}-sms")
    expect(delivery_log.status).to eq("sent")
    expect(delivery_log.channel).to eq("sms")
    expect(delivery_log.provider_name).to eq("twilio")
    expect(delivery_log.metadata["mode"]).to eq("stub")
    expect(delivery_log.metadata["attempts"].last["status"]).to eq("sent")
    expect(delivery_log.metadata["attempts"].last["channel"]).to eq("sms")
    expect(delivery_log.metadata["attempts"].last["external_response"]).to include("provider_message_id")
    expect(delivery_log.metadata["attempts"].last["timestamp"]).to be_present
  end

  it "is idempotent for already processed delivery logs" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document(doctor:, patient:)
    key = "doc-#{document.id}-whatsapp"

    2.times do
      described_class.perform_now(
        document_id: document.id,
        channel: "whatsapp",
        recipient: patient.phone,
        idempotency_key: key
      )
    end

    logs = DeliveryLog.where(idempotency_key: key)
    expect(logs.count).to eq(1)
    expect(logs.first.status).to eq("sent")
    expect(logs.first.attempt_number).to eq(1)
  end

  it "does not resend when a delivery with same idempotency key is already processing" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document(doctor:, patient:)
    key = "doc-#{document.id}-processing"

    DeliveryLog.create!(
      doctor: doctor,
      patient: patient,
      document: document,
      channel: "email",
      status: "processing",
      attempt_number: 1,
      recipient: patient.email,
      attempted_at: Time.current,
      idempotency_key: key,
      metadata: {}
    )

    expect do
      described_class.perform_now(
        document_id: document.id,
        channel: "email",
        recipient: patient.email,
        idempotency_key: key
      )
    end.not_to change(DeliveryLog, :count)

    log = DeliveryLog.find_by!(idempotency_key: key)
    expect(log.status).to eq("processing")
    expect(log.attempt_number).to eq(1)
  end

  it "uses exponential backoff for retries" do
    expect(described_class.retry_backoff_for(1)).to eq(5)
    expect(described_class.retry_backoff_for(2)).to eq(10)
    expect(described_class.retry_backoff_for(3)).to eq(20)
    expect(described_class.retry_backoff_for(4)).to eq(40)
    expect(described_class.retry_backoff_for(8)).to eq(300)
  end

  private

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dra Job #{suffix}",
      email: "job.#{suffix}@example.com",
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
      full_name: "Paciente Job #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1),
      email: "paciente.job.#{suffix}@example.com",
      phone: "1199999#{cpf_suffix}"
    )
  end

  def create_document(doctor:, patient:)
    prescription = Prescription.create!(
      doctor: doctor,
      patient: patient,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Conteudo inicial para envio",
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
