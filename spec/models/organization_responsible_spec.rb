require "rails_helper"
require "securerandom"

RSpec.describe OrganizationResponsible, type: :model do
  it "belongs to an organization" do
    responsible = described_class.new

    expect(responsible).not_to be_valid
    expect(responsible.errors[:organization]).to be_present
  end

  it "is valid when organization is present" do
    organization = Organization.create!(
      name: "Organizacao Resp #{SecureRandom.hex(4)}",
      kind: "autonomo"
    )

    responsible = described_class.new(organization: organization)

    expect(responsible).to be_valid
  end
end
