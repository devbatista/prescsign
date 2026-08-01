require "rails_helper"

RSpec.describe Substance, type: :model do
  it "exige o nome" do
    expect(described_class.new(name: nil)).not_to be_valid
  end

  it "impede nome duplicado (case-insensitive)" do
    described_class.create!(name: "Clonazepam")
    duplicate = described_class.new(name: "clonazepam")

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:name]).to be_present
  end

  it "normaliza nome, lista e sncr_type" do
    substance = described_class.new(name: "  clonazepam  ", list_344: " B1 ", sncr_type: " nrb ")

    substance.validate

    expect(substance.name).to eq("clonazepam")
    expect(substance.list_344).to eq("B1")
    expect(substance.sncr_type).to eq("NRB")
  end

  it "aceita sncr_type nulo (substância não controlada)" do
    substance = described_class.new(name: "Paracetamol", sncr_type: nil)

    expect(substance).to be_valid
    expect(substance.controlled?).to be(false)
  end

  it "rejeita um sncr_type desconhecido" do
    expect(described_class.new(name: "X", sncr_type: "XYZ")).not_to be_valid
  end

  it "expõe scopes de controladas e ativas" do
    controlled = described_class.create!(name: "Morfina", sncr_type: "NRA")
    common = described_class.create!(name: "Dipirona")
    inactive = described_class.create!(name: "Inativa", sncr_type: "RCE", active: false)

    expect(described_class.controlled).to include(controlled, inactive)
    expect(described_class.controlled).not_to include(common)
    expect(described_class.active).to include(controlled, common)
    expect(described_class.active).not_to include(inactive)
  end

  it "monta o rótulo com o tipo quando controlada" do
    expect(described_class.new(name: "Clonazepam", sncr_type: "NRB").label).to eq("Clonazepam (NRB)")
    expect(described_class.new(name: "Dipirona").label).to eq("Dipirona")
  end
end
