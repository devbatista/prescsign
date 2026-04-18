require "rails_helper"
require "securerandom"
require "digest"

RSpec.describe "Idempotency", type: :request do
  it "replays prescription creation response for same idempotency key and payload" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    token = access_token_for(doctor)
    key = "idem-prescription-create-1"

    payload = {
      prescription: {
        patient_id: patient.id,
        content: "Tomar 1 comprimido ao dia",
        issued_on: Date.current.to_s,
        valid_until: (Date.current + 7.days).to_s
      }
    }

    post "/v1/prescriptions",
         params: payload,
         headers: auth_headers(token, idempotency_key: key),
         as: :json

    expect(response).to have_http_status(:created)
    first_body = JSON.parse(response.body)

    expect do
      post "/v1/prescriptions",
           params: payload,
           headers: auth_headers(token, idempotency_key: key),
           as: :json
    end.not_to change(Prescription, :count)

    expect(response).to have_http_status(:created)
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    second_body = JSON.parse(response.body)
    expect(second_body.dig("prescription", "id")).to eq(first_body.dig("prescription", "id"))
  end

  it "returns conflict when idempotency key is reused with different payload" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    token = access_token_for(doctor)
    key = "idem-prescription-create-conflict"

    post "/v1/prescriptions",
         params: {
           prescription: {
             patient_id: patient.id,
             content: "Conteudo A",
             issued_on: Date.current.to_s
           }
         },
         headers: auth_headers(token, idempotency_key: key),
         as: :json
    expect(response).to have_http_status(:created)

    post "/v1/prescriptions",
         params: {
           prescription: {
             patient_id: patient.id,
             content: "Conteudo B",
             issued_on: Date.current.to_s
           }
         },
         headers: auth_headers(token, idempotency_key: key),
         as: :json

    expect(response).to have_http_status(:conflict)
    expect(JSON.parse(response.body)["error"]).to eq("Idempotency-Key already used with different payload")
  end

  it "replays sign response and does not duplicate signed audit log" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    prescription = create_prescription_with_document(doctor:, patient:)
    document = prescription.document
    token = access_token_for(doctor)
    key = "idem-document-sign-1"

    post "/v1/documents/#{document.id}/sign",
         headers: auth_headers(token, idempotency_key: key),
         as: :json

    expect(response).to have_http_status(:ok)
    expect(document.reload.status).to eq("sent")
    initial_signed_logs = AuditLog.where(document: document, action: "signed").count

    post "/v1/documents/#{document.id}/sign",
         headers: auth_headers(token, idempotency_key: key),
         as: :json

    expect(response).to have_http_status(:ok)
    expect(response.headers["Idempotency-Replayed"]).to eq("true")
    expect(AuditLog.where(document: document, action: "signed").count).to eq(initial_signed_logs)
  end

  private

  def host_headers
    { "HOST" => "localhost" }
  end

  def auth_headers(token, idempotency_key: nil)
    headers = host_headers.merge("Authorization" => "Bearer #{token}")
    headers["Idempotency-Key"] = idempotency_key if idempotency_key.present?
    headers
  end

  def access_token_for(doctor)
    Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil).first
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dra Idempotencia #{suffix}",
      email: "idempotencia.#{suffix}@example.com",
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
      full_name: "Paciente Idempotencia #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1)
    )
  end

  def create_prescription_with_document(doctor:, patient:)
    prescription = Prescription.create!(
      doctor: doctor,
      patient: patient,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Texto inicial da receita",
      issued_on: Date.current,
      status: "draft"
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
