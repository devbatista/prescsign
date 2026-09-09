require "rails_helper"
require "securerandom"

RSpec.describe Medication, type: :model do
  it "exige o nome" do
    medication = described_class.new(name: nil)

    expect(medication).not_to be_valid
    expect(medication.errors[:name]).to be_present
  end

  it "normaliza nome, campos em branco e EAN" do
    medication = described_class.new(
      name: "  Dipirona  ",
      active_ingredient: "   ",
      strength: " 500 mg ",
      ean: "789-1.234/5678 990"
    )

    medication.validate

    expect(medication.name).to eq("Dipirona")
    expect(medication.active_ingredient).to be_nil
    expect(medication.strength).to eq("500 mg")
    expect(medication.ean).to eq("78912345678990")
  end

  it "valida a forma farmacêutica" do
    expect(described_class.new(name: "X", pharmaceutical_form: "comprimido")).to be_valid
    invalid = described_class.new(name: "X", pharmaceutical_form: "elixir_magico")

    expect(invalid).not_to be_valid
    expect(invalid.errors[:pharmaceutical_form]).to be_present
  end

  it "valida a classe de controle (tarja)" do
    expect(described_class.new(name: "X", control_class: "tarja_preta")).to be_valid
    expect(described_class.new(name: "X", control_class: "arco_iris")).not_to be_valid
  end

  it "impede EAN duplicado (case-insensitive), ignorando em branco" do
    described_class.create!(name: "A", ean: "7891234567890")
    duplicate = described_class.new(name: "B", ean: "7891234567890")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:ean]).to be_present

    expect(described_class.new(name: "C", ean: nil)).to be_valid
    expect(described_class.new(name: "D", ean: "")).to be_valid
  end

  it "expõe o scope de ativos" do
    active = described_class.create!(name: "Ativo", active: true)
    described_class.create!(name: "Inativo", active: false)

    expect(described_class.active).to include(active)
    expect(described_class.active.map(&:active)).to all(be(true))
  end

  it "monta o rótulo com nome e concentração" do
    expect(described_class.new(name: "Dipirona", strength: "500 mg").label).to eq("Dipirona 500 mg")
    expect(described_class.new(name: "Dipirona").label).to eq("Dipirona")
  end

  # A tarja publicada pela CMED é uma segunda fonte, independente da nossa
  # curadoria: quando ela diz "controlado" e a base de substâncias não classifica
  # nada, o produto não pode ser tratado como comum.
  describe "#unclassified_controlled?" do
    it "aponta a contradição quando a tarja é de controlado e falta substância" do
      expect(described_class.new(name: "X", control_class: "tarja_preta")).to be_unclassified_controlled
      expect(described_class.new(name: "X", control_class: "tarja_vermelha_retencao")).to be_unclassified_controlled
    end

    it "não aponta contradição para tarja que não implica controle especial" do
      # Tarja vermelha "pura" é venda sob prescrição, não controle; "- (*)" na
      # fonte da CMED vira nulo, que não afirma nada.
      expect(described_class.new(name: "X", control_class: "tarja_vermelha")).not_to be_unclassified_controlled
      expect(described_class.new(name: "X", control_class: "comum")).not_to be_unclassified_controlled
      expect(described_class.new(name: "X", control_class: nil)).not_to be_unclassified_controlled
    end

    it "some quando o produto ganha uma substância controlada" do
      medication = described_class.create!(name: "Rivotril #{SecureRandom.hex(3)}", control_class: "tarja_preta")
      expect(medication).to be_unclassified_controlled

      medication.substances << Substance.create!(name: "clonazepam #{SecureRandom.hex(3)}", sncr_type: "NRB")

      expect(medication.reload).not_to be_unclassified_controlled
    end

    it "permanece quando a substância vinculada não é controlada" do
      medication = described_class.create!(name: "Composto #{SecureRandom.hex(3)}", control_class: "tarja_preta")
      medication.substances << Substance.create!(name: "excipiente #{SecureRandom.hex(3)}")

      expect(medication.reload).to be_unclassified_controlled
    end
  end

  it "lista a fila de curadoria no scope unclassified_controlled" do
    pending_item = described_class.create!(name: "Pendente #{SecureRandom.hex(3)}", control_class: "tarja_preta")
    classified = described_class.create!(name: "Classificado #{SecureRandom.hex(3)}", control_class: "tarja_preta")
    classified.substances << Substance.create!(name: "morfina #{SecureRandom.hex(3)}", sncr_type: "NRA")
    common = described_class.create!(name: "Comum #{SecureRandom.hex(3)}", control_class: "comum")

    result = described_class.unclassified_controlled

    expect(result).to include(pending_item)
    expect(result).not_to include(classified, common)
  end
end
