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
end
