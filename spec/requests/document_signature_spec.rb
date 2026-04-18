require "rails_helper"
require "securerandom"
require "digest"

RSpec.describe "Digital signature flow", type: :request do
  it "signs an issued document and updates statuses/metadata" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    prescription = create_prescription_with_document(doctor:, patient:)
    token = access_token_for(doctor)

    post "/v1/documents/#{prescription.document.id}/sign", headers: auth_headers(token), as: :json

    expect(response).to have_http_status(:ok)
    request_id = response.headers["X-Request-Id"]
    body = JSON.parse(response.body)
    expect(body["status"]).to eq("sent")
    expect(body["signed_at"]).to be_present
    expect(body.dig("metadata", "signature", "method")).to eq("internal_mvp")
    expect(body.dig("metadata", "signature", "signed_content_checksum").to_s.length).to eq(64)
    expect(prescription.reload.status).to eq("signed")

    actions = AuditLog.where(document_id: prescription.document.id).pluck(:action)
    expect(actions).to include("signed", "status_changed")
    expect(AuditLog.where(document_id: prescription.document.id).where.not(request_id: request_id)).not_to exist
  end

  it "blocks second signing attempt for the same document" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    prescription = create_prescription_with_document(doctor:, patient:)
    token = access_token_for(doctor)

    post "/v1/documents/#{prescription.document.id}/sign", headers: auth_headers(token), as: :json
    expect(response).to have_http_status(:ok)

    post "/v1/documents/#{prescription.document.id}/sign", headers: auth_headers(token), as: :json
    expect(response).to have_http_status(:forbidden)
  end

  it "keeps resource immutable after signing" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    prescription = create_prescription_with_document(doctor:, patient:)
    token = access_token_for(doctor)

    post "/v1/documents/#{prescription.document.id}/sign", headers: auth_headers(token), as: :json
    expect(response).to have_http_status(:ok)

    patch "/v1/prescriptions/#{prescription.id}", params: {
      prescription: { content: "Tentativa de alteracao indevida" }
    }, headers: auth_headers(token), as: :json

    expect(response).to have_http_status(:forbidden)
  end

  it "revokes signed document when integrity check detects content mismatch" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    prescription = create_prescription_with_document(doctor:, patient:)
    token = access_token_for(doctor)

    post "/v1/documents/#{prescription.document.id}/sign", headers: auth_headers(token), as: :json
    expect(response).to have_http_status(:ok)

    prescription.update_column(:content, "Conteudo adulterado fora do fluxo")

    post "/v1/documents/#{prescription.document.id}/integrity_check", headers: auth_headers(token), as: :json

    expect(response).to have_http_status(:ok)
    request_id = response.headers["X-Request-Id"]
    body = JSON.parse(response.body)
    expect(body["valid"]).to be(false)
    expect(body.dig("document", "status")).to eq("revoked")
    expect(prescription.reload.status).to eq("cancelled")
    expect(AuditLog.where(document_id: prescription.document.id, action: "revoked")).to exist
    integrity_audit = AuditLog.where(document_id: prescription.document.id, request_id: request_id)
    expect(integrity_audit.where(action: "updated", after_data: { "integrity" => "invalid" })).to exist
    expect(integrity_audit.where(action: "status_changed", after_data: { "status" => "revoked" })).to exist
    expect(integrity_audit.where(action: "status_changed", after_data: { "status" => "cancelled" })).to exist
    expect(integrity_audit.where(action: "revoked")).to exist
  end

  private

  def host_headers
    { "HOST" => "localhost" }
  end

  def auth_headers(token)
    host_headers.merge("Authorization" => "Bearer #{token}")
  end

  def access_token_for(doctor)
    Warden::JWTAuth::UserEncoder.new.call(doctor.user, :user, nil).first
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dra Assinatura #{suffix}",
      email: "assinatura.#{suffix}@example.com",
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
      full_name: "Paciente Assinatura #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1)
    )
  end

  def create_prescription_with_document(doctor:, patient:, status: "draft")
    prescription = Prescription.create!(
      doctor: doctor,
      patient: patient,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Conteudo inicial da receita",
      issued_on: Date.current,
      status: status
    )
    document = Document.create!(
      doctor: doctor,
      patient: patient,
      documentable: prescription,
      kind: "prescription",
      code: SecureRandom.alphanumeric(10).upcase,
      status: "issued",
      issued_on: Date.current,
      current_version: 1
    )
    DocumentVersion.create!(
      document: document,
      version_number: 1,
      content: prescription.content,
      checksum: Digest::SHA256.hexdigest(prescription.content),
      generated_at: Time.current
    )
    prescription
  end
end
