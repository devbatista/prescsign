require "rails_helper"
require "securerandom"

RSpec.describe SncrNumbering, type: :model do
  describe "validações" do
    it "é válido quando disponível e bem formado" do
      expect(build_numbering).to be_valid
    end

    it "rejeita um sncr_type desconhecido" do
      numbering = build_numbering(sncr_type: "XYZ")

      expect(numbering).not_to be_valid
      expect(numbering.errors[:sncr_type]).to be_present
    end

    it "rejeita número fora do formato nacional" do
      numbering = build_numbering(number: "12345")

      expect(numbering).not_to be_valid
      expect(numbering.errors[:number]).to be_present
    end

    it "rejeita número duplicado" do
      build_numbering(number: "2411.1-00.0000001").save!
      duplicate = build_numbering(number: "2411.1-00.0000001")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:number]).to be_present
    end

    it "exige receita e consumed_at quando consumido" do
      numbering = build_numbering(status: "consumed")

      expect(numbering).not_to be_valid
      expect(numbering.errors[:prescription]).to be_present
      expect(numbering.errors[:consumed_at]).to be_present
    end

    it "não aceita receita vinculada quando disponível" do
      profile = build_doctor_profile
      numbering = build_numbering(doctor_profile: profile, prescription: create_prescription(profile))

      expect(numbering).not_to be_valid
      expect(numbering.errors[:prescription]).to be_present
    end
  end

  describe ".consume_next!" do
    it "consome o menor número disponível do tipo e o vincula à receita" do
      profile = build_doctor_profile
      prescription = create_prescription(profile)
      build_numbering(doctor_profile: profile, number: "2411.1-00.0000003").save!
      build_numbering(doctor_profile: profile, number: "2411.1-00.0000001").save!
      build_numbering(doctor_profile: profile, number: "2411.1-00.0000002").save!

      consumed = described_class.consume_next!(doctor_profile: profile, sncr_type: "NRA", prescription: prescription)

      expect(consumed.number).to eq("2411.1-00.0000001")
      expect(consumed).to be_consumed
      expect(consumed.prescription).to eq(prescription)
      expect(consumed.consumed_at).to be_present
    end

    it "levanta PoolEmpty quando não há número do tipo" do
      profile = build_doctor_profile
      prescription = create_prescription(profile)

      expect {
        described_class.consume_next!(doctor_profile: profile, sncr_type: "RCE", prescription: prescription)
      }.to raise_error(SncrNumbering::PoolEmpty)
    end

    it "não consome número de outro médico" do
      owner = build_doctor_profile
      other = build_doctor_profile
      prescription = create_prescription(other)
      build_numbering(doctor_profile: owner, number: "2411.1-00.0000001").save!

      expect {
        described_class.consume_next!(doctor_profile: other, sncr_type: "NRA", prescription: prescription)
      }.to raise_error(SncrNumbering::PoolEmpty)
    end
  end

  describe ".balance_for" do
    it "conta os disponíveis por tipo" do
      profile = build_doctor_profile
      prescription = create_prescription(profile)
      build_numbering(doctor_profile: profile, sncr_type: "NRA", number: "2411.1-00.0000001").save!
      build_numbering(doctor_profile: profile, sncr_type: "NRA", number: "2411.1-00.0000002").save!
      build_numbering(doctor_profile: profile, sncr_type: "RCE", number: "2602.6-53.0000001").save!
      described_class.consume_next!(doctor_profile: profile, sncr_type: "NRA", prescription: prescription)

      expect(described_class.balance_for(profile)).to eq("NRA" => 1, "RCE" => 1)
    end
  end

  describe ".import_numbers!" do
    it "persiste a lista de números disponíveis" do
      profile = build_doctor_profile
      count = described_class.import_numbers!(
        doctor_profile: profile,
        sncr_type: "NRA",
        numbers: [ "2411.1-00.0000001", "2411.1-00.0000002" ]
      )

      expect(count).to eq(2)
      expect(described_class.available.for_doctor(profile).count).to eq(2)
    end
  end

  describe ".expand_range / .import_range!" do
    it "expande um bloco contínuo em números individuais" do
      numbers = described_class.expand_range("2602.6-53.0000001", "2602.6-53.0000003")

      expect(numbers).to eq(%w[2602.6-53.0000001 2602.6-53.0000002 2602.6-53.0000003])
    end

    it "persiste o bloco via import_range!" do
      profile = build_doctor_profile
      count = described_class.import_range!(
        doctor_profile: profile,
        sncr_type: "RCE",
        first: "2602.6-53.0000001",
        last: "2602.6-53.0000010"
      )

      expect(count).to eq(10)
      expect(described_class.available.for_doctor(profile).of_type("RCE").count).to eq(10)
    end

    it "recusa faixa com prefixos distintos" do
      expect {
        described_class.expand_range("2602.6-53.0000001", "2411.1-00.0000010")
      }.to raise_error(ArgumentError)
    end

    it "recusa faixa invertida" do
      expect {
        described_class.expand_range("2602.6-53.0000010", "2602.6-53.0000001")
      }.to raise_error(ArgumentError)
    end
  end

  def build_numbering(**overrides)
    profile = overrides[:doctor_profile] || build_doctor_profile
    described_class.new({
      doctor_profile: profile,
      sncr_type: "NRA",
      number: "2411.1-00.0000001",
      status: "available",
      obtained_at: Time.current
    }.merge(overrides.except(:doctor_profile)))
  end

  def build_doctor_profile
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr Numbering #{suffix}",
      email: "dr.numbering.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload.doctor_profile
  end

  def create_prescription(doctor_profile)
    user = doctor_profile.user
    patient = Patient.create!(
      doctor: user,
      organization: user.current_organization,
      full_name: "Paciente Numbering",
      cpf: SecureRandom.random_number(10**11).to_s.rjust(11, "0"),
      birth_date: Date.new(1990, 1, 1)
    )
    Prescription.create!(
      doctor: user,
      patient: patient,
      organization: patient.organization,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Uso continuo",
      issued_on: Date.current,
      status: "draft"
    )
  end
end
