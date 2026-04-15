require "rails_helper"

RSpec.describe Deliveries::ResponseValidator do
  it "normalizes valid provider response" do
    result = described_class.validate!(
      "status" => "sent",
      "provider_name" => "twilio",
      "provider_message_id" => "abc-123",
      "metadata" => { "foo" => "bar" }
    )

    expect(result).to eq(
      status: "sent",
      provider_name: "twilio",
      provider_message_id: "abc-123",
      metadata: { "foo" => "bar" }
    )
  end

  it "raises when response is missing required keys" do
    expect do
      described_class.validate!(status: "sent", provider_name: "twilio")
    end.to raise_error(Deliveries::UnexpectedProviderResponseError)
  end
end
