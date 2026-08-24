require "rails_helper"
require "securerandom"

RSpec.describe Deliveries::AdapterFactory do
  it "returns email adapter for email channel" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document(doctor:, patient:)

    adapter = described_class.build(
      channel: "email",
      document: document,
      recipient: patient.email
    )

    expect(adapter).to be_a(Deliveries::Adapters::EmailAdapter)
  end

  it "returns channel adapter for sms" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document(doctor:, patient:)

    adapter = described_class.build(
      channel: "sms",
      document: document,
      recipient: patient.phone
    )

    expect(adapter).to be_a(Deliveries::Adapters::SmsAdapter)
  end

  it "considera disponível apenas o canal com provedor integrado" do
    allow(Deliveries::Adapters::WhatsappAdapter).to receive(:available?).and_return(false)

    expect(described_class.available?("email")).to be(true)
    expect(described_class.available?(" EMAIL ")).to be(true)
    expect(described_class.available?("sms")).to be(false)
    expect(described_class.available?("whatsapp")).to be(false)
    expect(described_class.available?("carta")).to be(false)
    expect(described_class.available_channels).to eq(%w[email])
  end

  it "passa a oferecer WhatsApp quando o adapter se declara disponível" do
    allow(Deliveries::Adapters::WhatsappAdapter).to receive(:available?).and_return(true)

    expect(described_class.available?("whatsapp")).to be(true)
    expect(described_class.available_channels).to eq(%w[email whatsapp])
  end

  private

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dra Factory #{suffix}",
      email: "factory.#{suffix}@example.com",
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
      full_name: "Paciente Factory #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1),
      email: "paciente.factory.#{suffix}@example.com",
      phone: "1199999#{cpf_suffix}"
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
