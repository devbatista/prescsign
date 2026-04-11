require "rails_helper"
require "securerandom"
require "digest"

RSpec.describe "Document emission flows", type: :request do
  describe "Prescriptions" do
    it "creates prescription with initial document/version and audit trail" do
      doctor = create_confirmed_doctor
      patient = create_patient(doctor:)
      token = access_token_for(doctor)

      post "/v1/prescriptions", params: {
        prescription: {
          patient_id: patient.id,
          content: "Tomar 1 comprimido ao dia",
          issued_on: Date.current.to_s,
          valid_until: (Date.current + 7).to_s
        }
      }, headers: auth_headers(token), as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body.dig("prescription", "status")).to eq("draft")
      expect(body.dig("document", "status")).to eq("issued")
      expect(body.dig("latest_version", "version_number")).to eq(1)
      expect(body.dig("latest_version", "checksum").to_s.length).to eq(64)

      prescription_id = body.dig("prescription", "id")
      prescription = Prescription.find(prescription_id)
      actions = AuditLog.where(document: prescription.document).pluck(:action)
      expect(actions).to include("created", "status_changed")
    end

    it "updates a draft prescription and appends version with checksum" do
      doctor = create_confirmed_doctor
      patient = create_patient(doctor:)
      prescription = create_prescription_with_document(doctor:, patient:)
      token = access_token_for(doctor)

      patch "/v1/prescriptions/#{prescription.id}", params: {
        prescription: { content: "Atualizado: tomar 2 comprimidos ao dia" }
      }, headers: auth_headers(token), as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body.dig("document", "current_version")).to eq(2)
      expect(body.dig("latest_version", "version_number")).to eq(2)
      expect(body.dig("latest_version", "checksum").to_s.length).to eq(64)
      expect(AuditLog.where(resource: prescription, action: "updated")).to exist
    end

    it "blocks update when prescription is signed" do
      doctor = create_confirmed_doctor
      patient = create_patient(doctor:)
      prescription = create_prescription_with_document(doctor:, patient:, status: "signed")
      token = access_token_for(doctor)

      patch "/v1/prescriptions/#{prescription.id}", params: {
        prescription: { content: "Nao deveria atualizar" }
      }, headers: auth_headers(token), as: :json

      expect(response).to have_http_status(:forbidden)
    end

    it "revokes document and prescription and logs status transition" do
      doctor = create_confirmed_doctor
      patient = create_patient(doctor:)
      prescription = create_prescription_with_document(doctor:, patient:)
      token = access_token_for(doctor)

      post "/v1/prescriptions/#{prescription.id}/revoke", params: {
        revoke: { reason: "Paciente solicitou cancelamento" }
      }, headers: auth_headers(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(prescription.reload.status).to eq("cancelled")
      expect(prescription.document.reload.status).to eq("revoked")
      expect(AuditLog.where(resource: prescription.document, action: "revoked")).to exist
      expect(AuditLog.where(resource: prescription.document, action: "status_changed")).to exist
    end

    it "renders prescription PDF template for owner doctor" do
      doctor = create_confirmed_doctor
      patient = create_patient(doctor:)
      prescription = create_prescription_with_document(doctor:, patient:)
      token = access_token_for(doctor)

      get "/v1/prescriptions/#{prescription.id}/pdf", headers: auth_headers(token)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to include("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("receita-#{prescription.code}-v1.pdf")
      expect(response.body).to start_with("%PDF")
    end

    it "blocks prescription PDF access for non-owner doctor" do
      owner = create_confirmed_doctor
      patient = create_patient(doctor: owner)
      prescription = create_prescription_with_document(doctor: owner, patient:)
      outsider = create_confirmed_doctor
      outsider_token = access_token_for(outsider)

      get "/v1/prescriptions/#{prescription.id}/pdf", headers: auth_headers(outsider_token)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "Medical certificates" do
    it "creates medical certificate with initial document/version and audit trail" do
      doctor = create_confirmed_doctor
      patient = create_patient(doctor:)
      token = access_token_for(doctor)

      post "/v1/medical_certificates", params: {
        medical_certificate: {
          patient_id: patient.id,
          content: "Afastamento por 3 dias",
          issued_on: Date.current.to_s,
          rest_start_on: Date.current.to_s,
          rest_end_on: (Date.current + 3).to_s,
          icd_code: "J11"
        }
      }, headers: auth_headers(token), as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body.dig("medical_certificate", "status")).to eq("draft")
      expect(body.dig("document", "status")).to eq("issued")
      expect(body.dig("latest_version", "version_number")).to eq(1)
      expect(body.dig("latest_version", "checksum").to_s.length).to eq(64)
    end

    it "revokes medical certificate document and logs transition" do
      doctor = create_confirmed_doctor
      patient = create_patient(doctor:)
      medical_certificate = create_medical_certificate_with_document(doctor:, patient:)
      token = access_token_for(doctor)

      post "/v1/medical_certificates/#{medical_certificate.id}/revoke", headers: auth_headers(token), as: :json

      expect(response).to have_http_status(:ok)
      expect(medical_certificate.reload.status).to eq("cancelled")
      expect(medical_certificate.document.reload.status).to eq("revoked")
      expect(AuditLog.where(resource: medical_certificate.document, action: "status_changed")).to exist
    end

    it "renders medical certificate PDF template for owner doctor" do
      doctor = create_confirmed_doctor
      patient = create_patient(doctor:)
      medical_certificate = create_medical_certificate_with_document(doctor:, patient:)
      token = access_token_for(doctor)

      get "/v1/medical_certificates/#{medical_certificate.id}/pdf", headers: auth_headers(token)

      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to include("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("atestado-#{medical_certificate.code}-v1.pdf")
      expect(response.body).to start_with("%PDF")
    end

    it "blocks medical certificate PDF access for non-owner doctor" do
      owner = create_confirmed_doctor
      patient = create_patient(doctor: owner)
      medical_certificate = create_medical_certificate_with_document(doctor: owner, patient:)
      outsider = create_confirmed_doctor
      outsider_token = access_token_for(outsider)

      get "/v1/medical_certificates/#{medical_certificate.id}/pdf", headers: auth_headers(outsider_token)

      expect(response).to have_http_status(:not_found)
    end
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
      full_name: "Dra Emissao #{suffix}",
      email: "emissao.#{suffix}@example.com",
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
      full_name: "Paciente Emissao #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1)
    )
  end

  def create_prescription_with_document(doctor:, patient:, status: "draft")
    prescription = Prescription.create!(
      doctor: doctor,
      patient: patient,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Texto inicial da receita",
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

  def create_medical_certificate_with_document(doctor:, patient:, status: "draft")
    medical_certificate = MedicalCertificate.create!(
      doctor: doctor,
      patient: patient,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Texto inicial do atestado",
      issued_on: Date.current,
      rest_start_on: Date.current,
      rest_end_on: Date.current + 2,
      status: status
    )
    document = Document.create!(
      doctor: doctor,
      patient: patient,
      documentable: medical_certificate,
      kind: "medical_certificate",
      code: SecureRandom.alphanumeric(10).upcase,
      status: "issued",
      issued_on: Date.current,
      current_version: 1
    )
    DocumentVersion.create!(
      document: document,
      version_number: 1,
      content: medical_certificate.content,
      checksum: Digest::SHA256.hexdigest(medical_certificate.content),
      generated_at: Time.current
    )
    medical_certificate
  end
end
