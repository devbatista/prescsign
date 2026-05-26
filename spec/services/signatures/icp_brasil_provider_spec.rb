require "rails_helper"
require "base64"
require "stringio"

RSpec.describe Signatures::IcpBrasilProvider do
  it "fails fast when provider credentials are missing" do
    provider = described_class.new(base_url: nil, api_key: nil)

    expect do
      provider.sign_pdf!(
        document: instance_double(Document),
        pdf_io: StringIO.new("%PDF"),
        signer: instance_double(User)
      )
    end.to raise_error(Signatures::SignatureError, /base URL/)
  end

  it "maps provider response into signature result" do
    provider = described_class.new(base_url: "https://assinador.example", api_key: "secret")
    signed_pdf = "%PDF signed"

    result = provider.send(
      :build_result,
      {
        "signed_pdf_base64" => Base64.strict_encode64(signed_pdf),
        "provider" => "assinador_sandbox",
        "method" => "icp_brasil_pades",
        "policy" => "AD-RB",
        "certificate_subject" => "CN=Médico Teste",
        "signed_at" => "2026-05-13T12:00:00Z",
        "timestamped" => true,
        "validation_status" => "valid",
        "metadata" => { "request_id" => "provider-req-1" }
      }
    )

    expect(result.signed_pdf).to eq(signed_pdf)
    expect(result.provider).to eq("assinador_sandbox")
    expect(result.policy).to eq("AD-RB")
    expect(result.timestamped).to be(true)
    expect(result.raw_metadata).to eq("request_id" => "provider-req-1")
  end
end
