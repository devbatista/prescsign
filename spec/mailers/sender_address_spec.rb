require "rails_helper"
require "securerandom"

RSpec.describe "Remetente dos e-mails" do
  let(:from_email) { Rails.application.config.x.smtp.from_email }
  let(:brand) { Rails.application.config.x.smtp.from_name }

  describe Mailers::SenderAddress do
    it "usa o nome institucional por padrão" do
      expect(parse(described_class.default)).to eq([brand, from_email])
    end

    it "credita o profissional sem trocar o endereço do domínio verificado" do
      address = described_class.on_behalf_of("Dr. João Silva")

      expect(parse(address)).to eq(["Dr. João Silva via #{brand}", from_email])
    end

    it "cai no institucional quando não há nome" do
      expect(described_class.on_behalf_of(nil)).to eq(described_class.default)
      expect(described_class.on_behalf_of("")).to eq(described_class.default)
    end
  end

  describe DocumentDeliveryMailer do
    it "envia ao paciente em nome do médico" do
      doctor = create_confirmed_doctor(full_name: "Joana Prado", gender: "female")
      patient = create_patient(doctor:)
      document = create_document(doctor:, patient:)

      mail = described_class.with(document:, recipient: patient.email).notify_document

      expect(parse(mail[:from].value)).to eq(["Dra. Joana Prado via #{brand}", from_email])
      expect(mail.from).to eq([from_email])
    end

    it "não duplica o título quando o nome cadastrado já o traz" do
      doctor = create_confirmed_doctor(full_name: "Dra. Joana Prado")
      patient = create_patient(doctor:)
      document = create_document(doctor:, patient:)

      mail = described_class.with(document:, recipient: patient.email).notify_document

      expect(parse(mail[:from].value)).to eq(["Dra. Joana Prado via #{brand}", from_email])
    end
  end

  describe DoctorAccountMailer do
    it "envia e-mail de plataforma com o nome institucional" do
      doctor = create_confirmed_doctor(full_name: "Joana Prado")
      organization = doctor.current_organization
      token = doctor.send(:set_reset_password_token)

      mail = described_class.with(user: doctor, organization:, token:).account_setup

      expect(parse(mail[:from].value)).to eq([brand, from_email])
    end
  end

  private

  # O Mail só cita o display name quando o RFC exige; comparar os campos
  # decodificados mantém o teste sobre o conteúdo, não sobre o quoting.
  def parse(value)
    address = Mail::Address.new(value)
    [address.display_name, address.address]
  end

  def create_confirmed_doctor(full_name:, gender: nil)
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: full_name,
      email: "sender.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      gender: gender,
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
      full_name: "Paciente Sender #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1),
      email: "paciente.sender.#{suffix}@example.com"
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
