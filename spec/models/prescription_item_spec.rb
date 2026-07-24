require "rails_helper"
require "securerandom"

RSpec.describe PrescriptionItem, type: :model do
  it "exige o nome do medicamento" do
    item = build_item(name: nil)

    expect(item).not_to be_valid
    expect(item.errors[:name]).to be_present
  end

  it "normaliza nome e campos em branco" do
    item = build_item(name: "  Amoxicilina  ", active_ingredient: "   ", strength: " 500 mg ")

    item.validate

    expect(item.name).to eq("Amoxicilina")
    expect(item.active_ingredient).to be_nil
    expect(item.strength).to eq("500 mg")
  end

  it "atribui a primeira posicao automaticamente" do
    prescription = create_prescription
    item = prescription.prescription_items.build(name: "Dipirona")

    item.validate

    expect(item.position).to eq(1)
  end

  it "incrementa a posicao ao acrescentar itens" do
    prescription = create_prescription
    prescription.prescription_items.create!(name: "Dipirona")
    second = prescription.prescription_items.create!(name: "Amoxicilina")

    expect(second.position).to eq(2)
  end

  it "respeita a posicao informada explicitamente" do
    prescription = create_prescription
    item = prescription.prescription_items.build(name: "Losartana", position: 5)

    item.validate

    expect(item.position).to eq(5)
  end

  it "impede posicoes duplicadas na mesma receita" do
    prescription = create_prescription
    prescription.prescription_items.create!(name: "Dipirona", position: 1)
    duplicate = prescription.prescription_items.build(name: "Amoxicilina", position: 1)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:position]).to be_present
  end

  it "retorna os itens ordenados por posicao" do
    prescription = create_prescription
    prescription.prescription_items.create!(name: "Terceiro", position: 3)
    prescription.prescription_items.create!(name: "Primeiro", position: 1)
    prescription.prescription_items.create!(name: "Segundo", position: 2)

    expect(prescription.reload.prescription_items.map(&:name)).to eq(%w[Primeiro Segundo Terceiro])
  end

  it "e removido junto com a receita" do
    prescription = create_prescription
    prescription.prescription_items.create!(name: "Dipirona")

    expect { prescription.destroy }.to change(described_class, :count).by(-1)
  end

  def build_item(**overrides)
    prescription = overrides[:prescription] || create_prescription
    described_class.new({ prescription: prescription, name: "Dipirona" }.merge(overrides.except(:prescription)))
  end

  def create_prescription
    doctor = build_doctor
    patient = build_patient(doctor: doctor)
    Prescription.create!(
      doctor: doctor,
      patient: patient,
      organization: patient.organization,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Uso continuo",
      issued_on: Date.current,
      status: "draft"
    )
  end

  def build_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr Item #{suffix}",
      email: "dr.item.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end

  def build_patient(doctor:)
    Patient.create!(
      doctor: doctor,
      organization: doctor.current_organization,
      full_name: "Paciente Item",
      cpf: SecureRandom.random_number(10**11).to_s.rjust(11, "0"),
      birth_date: Date.new(1989, 1, 1)
    )
  end
end
