require "rails_helper"
require "securerandom"
require "digest"

RSpec.describe Documents::SigningService do
  it "emits critical alert and re-raises when signature provider fails" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document(doctor:, patient:)

    signature_provider = instance_double(Signatures::InternalProvider)
    allow(signature_provider).to receive(:sign).and_raise(StandardError, "signature provider unavailable")
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

  private

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
      content: "Conteudo inicial para assinatura",
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
