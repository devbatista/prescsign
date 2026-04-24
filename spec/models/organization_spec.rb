require "rails_helper"

RSpec.describe Organization, type: :model do
  it "requires legal_name and cnpj for clinica/hospital" do
    organization = described_class.new(name: "Clinica Teste", kind: "clinica")

    expect(organization).not_to be_valid
    expect(organization.errors[:legal_name]).to be_present
    expect(organization.errors[:cnpj]).to be_present
  end

  it "allows autonomo without cnpj" do
    organization = described_class.new(name: "Autonomo Joao", kind: "autonomo")

    expect(organization).to be_valid
  end

  it "derives name from trade_name when name is not provided" do
    organization = described_class.create!(
      kind: "clinica",
      legal_name: "Clinica Horizonte LTDA",
      trade_name: "Horizonte",
      cnpj: "44.555.666/0001-77"
    )

    expect(organization.name).to eq("Horizonte")
  end

  it "derives name from legal_name when trade_name is not provided" do
    organization = described_class.create!(
      kind: "clinica",
      legal_name: "Clinica Sem Fantasia LTDA",
      cnpj: "98.765.432/0001-10"
    )

    expect(organization.name).to eq("Clinica Sem Fantasia LTDA")
  end

  it "normalizes cnpj and address/contact fields" do
    organization = described_class.create!(
      name: "Hospital Teste",
      kind: "hospital",
      legal_name: "Hospital Teste SA",
      cnpj: "11.222.333/0001-81",
      email: "FINANCEIRO@HOSPITAL.COM ",
      phone: "(11) 98888-7777",
      zip_code: "01234-567",
      state: "sp",
      country: "br"
    )

    expect(organization.cnpj).to eq("11222333000181")
    expect(organization.email).to eq("financeiro@hospital.com")
    expect(organization.phone).to eq("11988887777")
    expect(organization.zip_code).to eq("01234567")
    expect(organization.state).to eq("SP")
    expect(organization.country).to eq("BR")
  end
end
