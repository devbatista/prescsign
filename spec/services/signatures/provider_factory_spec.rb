require "rails_helper"

RSpec.describe Signatures::ProviderFactory do
  around do |example|
    original = Rails.application.config.x.signature_provider
    example.run
  ensure
    Rails.application.config.x.signature_provider = original
  end

  it "builds the internal provider by default" do
    Rails.application.config.x.signature_provider = "internal"

    expect(described_class.build).to be_a(Signatures::InternalProvider)
  end

  it "builds the ICP-Brasil provider when configured" do
    Rails.application.config.x.signature_provider = "icp_brasil"

    expect(described_class.build).to be_a(Signatures::IcpBrasilProvider)
  end
end
