require "rails_helper"
require "securerandom"

RSpec.describe Deliveries::ChannelDispatcher do
  it "delegates delivery to adapter selected by factory" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor:)
    document = create_document(doctor:, patient:)

    adapter = instance_double(Deliveries::Adapters::BaseAdapter)
    allow(Deliveries::AdapterFactory).to receive(:build).and_return(adapter)
    allow(adapter).to receive(:call).and_return({ status: "sent", provider_name: "fake" })

    result = described_class.new(
      document: document,
      channel: "sms",
      recipient: patient.phone
    ).call

    expect(result).to include(status: "sent", provider_name: "fake")
    expect(Deliveries::AdapterFactory).to have_received(:build)
  end

  private

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dra Dispatcher #{suffix}",
      email: "dispatcher.#{suffix}@example.com",
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
      full_name: "Paciente Dispatcher #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1),
      email: "paciente.dispatcher.#{suffix}@example.com",
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
