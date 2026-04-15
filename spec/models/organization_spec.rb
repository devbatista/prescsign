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

  it "normalizes cnpj and address/contact fields" do
    organization = described_class.create!(
      name: "Hospital Teste",
      kind: "hospital",
      legal_name: "Hospital Teste SA",
      cnpj: "12.345.678/0001-90",
      email: "FINANCEIRO@HOSPITAL.COM ",
      phone: "(11) 98888-7777",
      zip_code: "01234-567",
      state: "sp",
      country: "br"
    )

    expect(organization.cnpj).to eq("12345678000190")
    expect(organization.email).to eq("financeiro@hospital.com")
    expect(organization.phone).to eq("11988887777")
    expect(organization.zip_code).to eq("01234567")
    expect(organization.state).to eq("SP")
    expect(organization.country).to eq("BR")
  end
end
