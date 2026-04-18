require "rails_helper"
require "securerandom"

RSpec.describe "Audit logs query", type: :request do
  it "returns audit logs filtered by document_id" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document_with_prescription(doctor:, patient:)
    other_patient = create_patient(doctor:)
    other_document = create_document_with_prescription(doctor:, patient: other_patient)
    token = access_token_for(doctor)

    AuditLog.record!(actor: doctor, document: document, patient: patient, resource: document, action: "viewed", after_data: { context: "documents_show" })
    AuditLog.record!(actor: doctor, document: other_document, patient: other_patient, resource: other_document, action: "viewed", after_data: { context: "documents_show" })

    get v1_audit_logs_path(document_id: document.id), headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["data"]).not_to be_empty
    expect(body["data"].all? { |entry| entry["document_id"] == document.id }).to eq(true)
  end

  it "returns audit logs filtered by patient_id" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document_with_prescription(doctor:, patient:)
    token = access_token_for(doctor)

    AuditLog.record!(actor: doctor, document: document, patient: patient, resource: patient, action: "updated", before_data: { active: true }, after_data: { active: true })
    AuditLog.record!(actor: doctor, document: document, patient: patient, resource: document, action: "viewed", after_data: { context: "documents_show" })

    get v1_audit_logs_path(patient_id: patient.id), headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["data"]).not_to be_empty
    expect(body["data"].all? { |entry| entry["patient_id"] == patient.id }).to eq(true)
  end

  it "returns unprocessable_content when no filter is provided" do
    doctor = create_confirmed_doctor
    token = access_token_for(doctor)

    get v1_audit_logs_path, headers: auth_headers(token)

    expect(response).to have_http_status(:unprocessable_content)
    body = JSON.parse(response.body)
    messages = Array(body["errors"]).map { |entry| entry["message"] }
    expect(messages).to include("At least one filter is required: document_id or patient_id")
    expect(body["error_code"]).to eq("unprocessable_entity")
  end

  it "supports standard ordering and sorting metadata" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document_with_prescription(doctor:, patient:)
    token = access_token_for(doctor)

    older = 2.days.ago
    newer = 1.day.ago
    AuditLog.record!(actor: doctor, document: document, patient: patient, resource: document, action: "viewed", occurred_at: newer, after_data: { context: "new" })
    AuditLog.record!(actor: doctor, document: document, patient: patient, resource: document, action: "viewed", occurred_at: older, after_data: { context: "old" })

    get v1_audit_logs_path(document_id: document.id, sort_by: "occurred_at", sort_dir: "asc"), headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    occurred = body.fetch("data").map { |entry| entry["occurred_at"] }
    expect(occurred).to eq(occurred.sort)
    expect(body.dig("meta", "sort_by")).to eq("occurred_at")
    expect(body.dig("meta", "sort_dir")).to eq("asc")
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
      full_name: "Dra Auditoria #{suffix}",
      email: "auditoria.#{suffix}@example.com",
      cpf: "55555#{cpf_suffix}",
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
      full_name: "Paciente Auditoria #{suffix}",
      cpf: "77777#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1)
    )
  end

  def create_document_with_prescription(doctor:, patient:)
    prescription = Prescription.create!(
      doctor: doctor,
      patient: patient,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Conteudo para auditoria",
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
