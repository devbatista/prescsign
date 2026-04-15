require "rails_helper"
require "securerandom"

RSpec.describe "Document resend", type: :request do
  include ActiveJob::TestHelper

  before do
    clear_enqueued_jobs
  end

  it "queues document resend job for a valid channel" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:, email: "paciente.resend@example.com", phone: "11999999999")
    document = create_document(doctor:, patient:)
    token = access_token_for(doctor)

    expect do
      post "/v1/documents/#{document.id}/resend",
           params: { resend: { channel: "email" } },
           headers: auth_headers(token),
           as: :json
    end.to have_enqueued_job(DocumentChannelDeliveryJob)

    expect(response).to have_http_status(:accepted)
    body = JSON.parse(response.body)
    expect(body["document_id"]).to eq(document.id)
    expect(body["channel"]).to eq("email")
    expect(body["recipient"]).to eq("paciente.resend@example.com")
    expect(body["idempotency_key"]).to be_present
  end

  it "returns unprocessable_content when channel is invalid" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:, email: "paciente.resend@example.com")
    document = create_document(doctor:, patient:)
    token = access_token_for(doctor)

    expect do
      post "/v1/documents/#{document.id}/resend",
           params: { resend: { channel: "fax" } },
           headers: auth_headers(token),
           as: :json
    end.not_to have_enqueued_job(DocumentChannelDeliveryJob)

    expect(response).to have_http_status(:unprocessable_content)
  end

  it "returns not_found for doctor outside document scope" do
    owner = create_confirmed_doctor
    outsider = create_confirmed_doctor
    patient = create_patient(doctor: owner, email: "paciente.resend@example.com")
    document = create_document(doctor: owner, patient:)
    outsider_token = access_token_for(outsider)

    expect do
      post "/v1/documents/#{document.id}/resend",
           params: { resend: { channel: "email" } },
           headers: auth_headers(outsider_token),
           as: :json
    end.not_to have_enqueued_job(DocumentChannelDeliveryJob)

    expect(response).to have_http_status(:not_found)
  end

  private

  def host_headers
    { "HOST" => "localhost" }
  end

  def auth_headers(token)
    host_headers.merge("Authorization" => "Bearer #{token}")
  end

  def access_token_for(doctor)
    Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil).first
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dra Reenvio #{suffix}",
      email: "reenvio.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end

  def create_patient(doctor:, email: nil, phone: nil)
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    Patient.create!(
      doctor: doctor,
      full_name: "Paciente Reenvio #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1),
      email: email,
      phone: phone
    )
  end

  def create_document(doctor:, patient:, status: "sent")
    prescription = Prescription.create!(
      doctor: doctor,
      patient: patient,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Conteudo inicial para reenvio",
      issued_on: Date.current,
      status: "signed"
    )

    Document.create!(
      doctor: doctor,
      patient: patient,
      documentable: prescription,
      kind: "prescription",
      code: SecureRandom.alphanumeric(10).upcase,
      status: status,
      issued_on: Date.current,
      current_version: 1
    )
  end
end
