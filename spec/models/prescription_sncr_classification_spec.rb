require "rails_helper"
require "securerandom"

# Cobre a cadeia substância → medicamento → item → receita: a classificação SNCR
# passa a ser derivada do catálogo, não escolhida à mão.
RSpec.describe "Classificação SNCR derivada do catálogo", type: :model do
  describe Medication, "#effective_sncr_type" do
    it "é nil quando o medicamento não tem substância controlada" do
      medication = Medication.create!(name: "Dipirona")
      medication.substances << Substance.create!(name: "Dipirona sódica")

      expect(medication.effective_sncr_type).to be_nil
    end

    it "assume o tipo da substância controlada" do
      medication = Medication.create!(name: "Rivotril")
      medication.substances << Substance.create!(name: "Clonazepam", sncr_type: "NRB")

      expect(medication.effective_sncr_type).to eq("NRB")
    end

    it "assume o tipo mais restritivo quando há substâncias de tipos diferentes" do
      medication = Medication.create!(name: "Associação")
      medication.substances << Substance.create!(name: "Sub RET", sncr_type: "RET")
      medication.substances << Substance.create!(name: "Sub NRA", sncr_type: "NRA")

      # NRA precede RET em SNCR_TYPE_PRECEDENCE.
      expect(medication.effective_sncr_type).to eq("NRA")
    end
  end

  describe PrescriptionItem, "snapshot do sncr_type" do
    it "herda o tipo do medicamento controlado ao criar o item" do
      medication = controlled_medication("Clonazepam", "NRB")
      prescription = create_prescription
      item = prescription.prescription_items.create!(name: "Rivotril", medication: medication)

      expect(item.sncr_type).to eq("NRB")
    end

    it "fica sem tipo quando o item é digitado à mão (sem medication)" do
      prescription = create_prescription
      item = prescription.prescription_items.create!(name: "Chá caseiro")

      expect(item.sncr_type).to be_nil
    end

    it "mantém o snapshot mesmo se a substância mudar depois" do
      substance = Substance.create!(name: "Clonazepam", sncr_type: "NRB")
      medication = Medication.create!(name: "Rivotril")
      medication.substances << substance
      prescription = create_prescription
      item = prescription.prescription_items.create!(name: "Rivotril", medication: medication)

      substance.update!(sncr_type: "RCE")

      expect(item.reload.sncr_type).to eq("NRB")
    end
  end

  describe Prescription, "derivação a partir dos itens" do
    it "torna a receita controlada mesmo sem o médico marcar o tipo" do
      medication = controlled_medication("Clonazepam", "NRB")
      prescription = build_prescription(content: nil, prescription_items_attributes: [
        { name: "Rivotril", medication_id: medication.id }
      ])

      prescription.save!

      expect(prescription.controlled?).to be(true)
      expect(prescription.sncr_type).to eq("NRB")
    end

    it "a substância vence a escolha manual divergente" do
      medication = controlled_medication("Isotretinoína", "NRR")
      prescription = build_prescription(sncr_type: "NRB", content: nil, prescription_items_attributes: [
        { name: "Roacutan", medication_id: medication.id }
      ])

      prescription.save!

      expect(prescription.sncr_type).to eq("NRR")
    end

    it "preserva o tipo manual para receita em texto livre (sem itens do catálogo)" do
      prescription = build_prescription(sncr_type: "RCE", content: "Manipulado uso contínuo")

      prescription.save!

      expect(prescription.sncr_type).to eq("RCE")
    end

    it "barra receita com itens de tipos de controle diferentes" do
      nrb = controlled_medication("Clonazepam", "NRB")
      rce = controlled_medication("Testosterona", "RCE")
      prescription = build_prescription(content: nil, prescription_items_attributes: [
        { name: "Rivotril", medication_id: nrb.id },
        { name: "Durateston", medication_id: rce.id }
      ])

      expect(prescription).not_to be_valid
      expect(prescription.errors[:base].join).to include("tipos de controle diferentes")
    end

    it "permite vários itens do mesmo tipo controlado" do
      nrb_a = controlled_medication("Clonazepam", "NRB")
      nrb_b = controlled_medication("Diazepam", "NRB")
      prescription = build_prescription(content: nil, prescription_items_attributes: [
        { name: "Rivotril", medication_id: nrb_a.id },
        { name: "Valium", medication_id: nrb_b.id }
      ])

      expect(prescription).to be_valid
      prescription.save!
      expect(prescription.sncr_type).to eq("NRB")
    end
  end

  def controlled_medication(substance_name, sncr_type)
    medication = Medication.create!(name: "Med #{substance_name} #{SecureRandom.hex(3)}")
    medication.substances << Substance.create!(name: "#{substance_name} #{SecureRandom.hex(3)}", sncr_type: sncr_type)
    medication
  end

  def build_prescription(**overrides)
    doctor = overrides[:doctor] || build_doctor
    patient = overrides[:patient] || build_patient(doctor: doctor)

    Prescription.new({
      doctor: doctor,
      patient: patient,
      organization: patient.organization,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Uso continuo",
      issued_on: Date.current,
      status: "draft"
    }.merge(overrides.except(:doctor, :patient)))
  end

  def create_prescription
    build_prescription.tap(&:save!)
  end

  def build_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr SNCR #{suffix}",
      email: "dr.sncr.#{suffix}@example.com",
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
      full_name: "Paciente SNCR",
      cpf: SecureRandom.random_number(10**11).to_s.rjust(11, "0"),
      birth_date: Date.new(1989, 1, 1)
    )
  end
end
