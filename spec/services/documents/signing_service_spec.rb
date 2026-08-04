require "rails_helper"
require "securerandom"
require "digest"

RSpec.describe Documents::SigningService do
  it "emits critical alert and re-raises when signature provider fails" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document(doctor:, patient:)

    signature_provider = instance_double(Signatures::InternalProvider)
    allow(signature_provider).to receive(:sign_pdf!).and_raise(StandardError, "signature provider unavailable")
    allow(Documents::PdfRenderer).to receive(:new).and_return(instance_double(Documents::PdfRenderer, render: "%PDF unsigned"))
    allow(Observability::CriticalAlertService).to receive(:notify!)

    service = described_class.new(
      actor: doctor,
      request_id: "req-signature-critical",
      request_origin: "https://api.prescsign.local",
      signature_provider: signature_provider
    )

    expect do
      service.sign!(document: document)
    end.to raise_error(StandardError, "signature provider unavailable")

    expect(Observability::CriticalAlertService).to have_received(:notify!).with(
      hash_including(
        category: "signature_failure",
        exception: kind_of(StandardError),
        context: hash_including(
          document_id: document.id,
          user_id: doctor.id,
          request_id: "req-signature-critical"
        )
      )
    )
  end

  it "creates signed document version with attached provider PDF and signature metadata" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document(doctor:, patient:)
    signed_pdf = "%PDF signed"
    signature_provider = instance_double(Signatures::InternalProvider)
    signature_result = Signatures::SignatureResult.new(
      signed_pdf: signed_pdf,
      provider: "test_provider",
      method: "icp_brasil_pades",
      policy: "AD-RB",
      certificate_subject: "CN=Médico Teste",
      signed_at: Time.zone.parse("2026-05-13T12:00:00Z"),
      timestamped: true,
      validation_status: "valid"
    )

    allow(signature_provider).to receive(:sign_pdf!).and_return(signature_result)
    allow(Documents::PdfRenderer).to receive(:new).and_return(instance_double(Documents::PdfRenderer, render: "%PDF unsigned"))

    service = described_class.new(
      actor: doctor,
      request_id: "req-signature-success",
      request_origin: "https://api.prescsign.local",
      signature_provider: signature_provider
    )

    service.sign!(document: document)

    document.reload
    signed_version = document.document_versions.find_by!(version_number: 2)
    expect(document.status).to eq("sent")
    expect(document.current_version).to eq(2)
    expect(document.metadata.dig("signature", "method")).to eq("icp_brasil_pades")
    expect(document.metadata.dig("signature", "provider")).to eq("test_provider")
    expect(document.metadata.dig("signature", "signed_version")).to eq(2)
    expect(document.metadata.dig("signature", "signed_pdf_checksum")).to eq(Digest::SHA256.hexdigest(signed_pdf))
    expect(signed_version.checksum).to eq(Digest::SHA256.hexdigest(signed_pdf))
    expect(signed_version.pdf_file).to be_attached
  end

  it "enfileira a entrega ao paciente por email ao assinar (link seguro)" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    patient.update!(email: "paciente.entrega@example.com")
    document = create_document(doctor:, patient:)

    expect do
      described_class.new(actor: doctor, signature_provider: stub_signature_provider).sign!(document: document)
    end.to have_enqueued_job(DocumentChannelDeliveryJob).with(
      hash_including(channel: "email", recipient: "paciente.entrega@example.com", document_id: document.id)
    )
  end

  it "não enfileira entrega quando o paciente não tem email" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document(doctor:, patient:)

    expect do
      described_class.new(actor: doctor, signature_provider: stub_signature_provider).sign!(document: document)
    end.not_to have_enqueued_job(DocumentChannelDeliveryJob)
  end

  private

  def stub_signature_provider
    provider = instance_double(Signatures::InternalProvider)
    allow(provider).to receive(:sign_pdf!).and_return(
      Signatures::SignatureResult.new(
        signed_pdf: "%PDF signed", provider: "test_provider", method: "icp_brasil_pades",
        policy: "AD-RB", signed_at: Time.current, timestamped: true, validation_status: "valid"
      )
    )
    allow(Documents::PdfRenderer).to receive(:new).and_return(
      instance_double(Documents::PdfRenderer, render: "%PDF unsigned")
    )
    provider
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dra Signature Service #{suffix}",
      email: "sign.service.#{suffix}@example.com",
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
      full_name: "Paciente Signature Service #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1)
    )
  end

  def create_document(doctor:, patient:)
    prescription = Prescription.create!(
      doctor: doctor,
      patient: patient,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Conteúdo inicial para assinatura",
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

    document
  end
end
