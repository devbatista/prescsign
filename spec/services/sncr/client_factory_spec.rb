require "rails_helper"

RSpec.describe Sncr::ClientFactory do
  around do |example|
    original = Rails.application.config.x.sncr.fake
    example.run
    Rails.application.config.x.sncr.fake = original
  end

  it "constrói o cliente real quando o modo simulado está desligado" do
    Rails.application.config.x.sncr.fake = false

    expect(described_class.build).to be_a(Sncr::Client)
    expect(described_class).not_to be_fake
  end

  it "constrói o cliente simulado quando SNCR_FAKE está ligado" do
    Rails.application.config.x.sncr.fake = true

    expect(described_class.build).to be_a(Sncr::FakeClient)
    expect(described_class).to be_fake
  end

  it "repassa opções extras ao cliente real e as ignora no simulado" do
    Rails.application.config.x.sncr.fake = false
    expect(described_class.build(access_token: "jwt", base_url: "https://sncr.example")).to be_a(Sncr::Client)

    Rails.application.config.x.sncr.fake = true
    expect(described_class.build(access_token: "jwt", base_url: "https://sncr.example")).to be_a(Sncr::FakeClient)
  end
end
