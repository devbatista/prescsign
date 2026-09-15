require "rails_helper"
require "securerandom"

RSpec.describe Medication, type: :model do
  include ActiveSupport::Testing::TimeHelpers
  include WebSpecHelpers

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

    it "some quando a curadoria confirma que a tarja é ruído" do
      medication = described_class.create!(name: "Glicose #{SecureRandom.hex(3)}", control_class: "tarja_preta")
      expect(medication).to be_unclassified_controlled

      medication.update!(uncontrolled_confirmed: true, uncontrolled_confirmed_reason: "eletrólito; fora da 344/98")

      expect(medication.reload).not_to be_unclassified_controlled
    end
  end

  # Saída do ruído da CMED na fila de curadoria: sem ela, eletrólito com tarja
  # preta bloquearia a emissão todo mês, porque a reimportação sobrescreve a
  # tarja e desfaz qualquer correção manual.
  describe "confirmação de não controlado" do
    it "exige motivo ao confirmar" do
      medication = described_class.new(name: "X", control_class: "tarja_preta", uncontrolled_confirmed: true)

      expect(medication).not_to be_valid
      expect(medication.errors[:uncontrolled_confirmed_reason]).to be_present
    end

    it "guarda o instante, não um booleano, e preserva a data ao reconfirmar" do
      medication = described_class.create!(
        name: "X #{SecureRandom.hex(3)}", control_class: "tarja_preta",
        uncontrolled_confirmed: true, uncontrolled_confirmed_reason: "ruído"
      )
      first = medication.uncontrolled_confirmed_at
      expect(first).to be_present

      travel_to(1.day.from_now) { medication.update!(uncontrolled_confirmed: true) }

      expect(medication.reload.uncontrolled_confirmed_at).to be_within(1.second).of(first)
    end

    it "desconfirmar limpa motivo e autor, em qualquer ordem de atribuição" do
      user = create_user(organization: create_organization)
      medication = described_class.create!(
        name: "X #{SecureRandom.hex(3)}", control_class: "tarja_preta",
        uncontrolled_confirmed: true, uncontrolled_confirmed_reason: "ruído", uncontrolled_confirmed_by: user
      )

      # Motivo chega DEPOIS do desmarcar, como o formulário pode mandar.
      medication.update!(uncontrolled_confirmed: false, uncontrolled_confirmed_reason: "sobra do formulário")

      expect(medication.reload).to have_attributes(
        uncontrolled_confirmed_at: nil, uncontrolled_confirmed_reason: nil, uncontrolled_confirmed_by: nil
      )
    end
  end

  it "lista a fila de curadoria no scope unclassified_controlled" do
    pending_item = described_class.create!(name: "Pendente #{SecureRandom.hex(3)}", control_class: "tarja_preta")
    classified = described_class.create!(name: "Classificado #{SecureRandom.hex(3)}", control_class: "tarja_preta")
    classified.substances << Substance.create!(name: "morfina #{SecureRandom.hex(3)}", sncr_type: "NRA")
    common = described_class.create!(name: "Comum #{SecureRandom.hex(3)}", control_class: "comum")
    confirmed = described_class.create!(
      name: "Confirmado #{SecureRandom.hex(3)}", control_class: "tarja_preta",
      uncontrolled_confirmed: true, uncontrolled_confirmed_reason: "ruído da CMED"
    )

    result = described_class.unclassified_controlled

    expect(result).to include(pending_item)
    expect(result).not_to include(classified, common, confirmed)
  end
end
