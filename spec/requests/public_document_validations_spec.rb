require "rails_helper"
require "securerandom"
require "digest"

RSpec.describe "Public document validation", type: :request do
  it "returns valid document with minimal public data and qr code" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_prescription_document(doctor:, patient:, status: "issued")

    get "/v1/public/documents/#{document.code}/validation", headers: { "HOST" => "localhost" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)

    expect(body["valid"]).to be(true)
    expect(body["status_reason"]).to be_nil
    expect(body.dig("document", "code")).to eq(document.code)
    expect(body.dig("document", "kind")).to eq("prescription")
    expect(body.dig("document", "status")).to eq("issued")
    expect(body.dig("issuer", "full_name")).to eq(doctor.full_name)
    expect(body.dig("issuer", "license_number")).to eq(doctor.license_number)
    expect(body.dig("validation", "url")).to include("/v1/public/documents/#{document.code}/validation")
    expect(body.dig("validation", "qr_code_svg")).to include("<svg")

    expect(body.dig("document")).not_to have_key("doctor_id")
    expect(body.dig("document")).not_to have_key("patient_id")
    expect(body.dig("document")).not_to have_key("content")

    viewed_audit = AuditLog.find_by(document: document, action: "viewed")
    expect(viewed_audit).to be_present
    expect(viewed_audit.after_data["context"]).to eq("public_document_validation")
    expect(viewed_audit.request_id).to eq(response.headers["X-Request-Id"])
  end

  it "returns invalid for revoked document" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_prescription_document(doctor:, patient:, status: "revoked")

    get "/v1/public/documents/#{document.code}/validation", headers: { "HOST" => "localhost" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["valid"]).to be(false)
    expect(body["status_reason"]).to eq("revoked")
  end

  it "returns invalid for expired document" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_prescription_document(doctor:, patient:, status: "expired")

    get "/v1/public/documents/#{document.code}/validation", headers: { "HOST" => "localhost" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["valid"]).to be(false)
    expect(body["status_reason"]).to eq("expired")
  end

  it "returns not_found for unknown document code" do
    get "/v1/public/documents/CODEINEXIST/validation", headers: { "HOST" => "localhost" }

    expect(response).to have_http_status(:not_found)
    body = JSON.parse(response.body)
    expect(body["valid"]).to be(false)
    expect(body["error"]).to eq("Document not found")
  end

  private

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr. Public #{suffix}",
      email: "public.#{suffix}@example.com",
      cpf: "11111#{cpf_suffix}",
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
      full_name: "Paciente Public #{suffix}",
      cpf: "22222#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1)
    )
  end

  def create_prescription_document(doctor:, patient:, status:)
    prescription = Prescription.create!(
      doctor: doctor,
      patient: patient,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Uso oral por 5 dias",
      issued_on: Date.current,
      status: "draft"
    )
    document = Document.create!(
      doctor: doctor,
      patient: patient,
      documentable: prescription,
      kind: "prescription",
      code: SecureRandom.alphanumeric(10).upcase,
      status: status,
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
    document
  end
end
