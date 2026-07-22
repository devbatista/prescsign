require "rails_helper"
require "base64"

RSpec.describe Signatures::EvalCryptoCuboProvider do
  let(:document) { instance_double(Document, id: "doc-1", code: "ABC12345") }
  let(:user) { instance_double(User, id: 42) }

  it "fails fast when signing configuration is missing" do
    provider = described_class.new(base_url: nil, operator_id: nil, type: nil, format: nil)

    expect do
      provider.sign_pdf!(document: document, pdf_io: StringIO.new("%PDF"), signer: user)
    end.to raise_error(Signatures::SignatureError, /base URL/)
  end

  it "builds the configured sign path" do
    provider = described_class.new(
      base_url: "https://api.example",
      operator_id: "operator 1",
      type: "qualified",
      format: "attached"
    )

    expect(provider.send(:sign_path)).to eq(
      "/api/v1/electronic-signature-v4/operator+1/qualified/attached/sign"
    )
  end

  it "builds the configured verify path" do
    provider = described_class.new(
      base_url: "https://api.example",
      type: "qualified",
      format: "attached",
      verify_type: "qualified",
      verify_format: "attached",
      verify_signer: "signer-1",
      verify_package: "package-1"
    )

    expect(provider.send(:verify_path)).to eq(
      "/api/v1/electronic-signature-v4/verify/qualified/attached/signer-1/package-1"
    )
  end

  it "builds the signing payload with only documented fields and configured certificate data" do
    provider = described_class.new(
      base_url: "https://api.example",
      operator_id: "op",
      type: "qualified",
      format: "attached",
      alias_name: "cert-alias",
      pin: "123456"
    )

    payload = provider.send(:signature_payload, document: document, pdf_binary: "%PDF", signer: user)

    expect(payload).to eq(
      format: "attached",
      type: "qualified",
      documents: [{ content: Base64.strict_encode64("%PDF") }],
      alias: "cert-alias",
      pin: "123456"
    )
  end

  it "maps a signing response into a signature result" do
    provider = described_class.new(base_url: "https://api.example", operator_id: "op", type: "qualified", format: "attached")
    signed_pdf = "%PDF signed"

    result = provider.send(
      :build_signature_result,
      {
        "documents" => [
          {
            "content" => Base64.strict_encode64(signed_pdf),
            "signatureName" => "Assinatura 1",
            "signatureTime" => "2026-05-13T12:00:00Z"
          }
        ],
        "validationStatus" => "valid"
      }
    )

    expect(result.signed_pdf).to eq(signed_pdf)
    expect(result.provider).to eq("eval_crypto_cubo")
    expect(result.method).to eq("eval_crypto_cubo_pades")
    expect(result.validation_status).to eq("valid")
    expect(result.raw_metadata).not_to include("content")
    expect(result.raw_metadata.dig("document", "signatureName")).to eq("Assinatura 1")
  end

  it "maps a verification response into a verification result without retaining PDF content" do
    provider = described_class.new(base_url: "https://api.example", type: "qualified", format: "attached")

    result = provider.send(
      :build_verification_result,
      {
        "valid" => true,
        "validationStatus" => "valid",
        "documents" => [
          {
            "content" => Base64.strict_encode64("%PDF signed"),
            "signature" => { "subject" => "CN=Medico" }
          }
        ]
      }
    )

    expect(result.provider).to eq("eval_crypto_cubo")
    expect(result.valid).to be(true)
    expect(result.validation_status).to eq("valid")
    expect(result.signatures).to eq([{ "subject" => "CN=Medico" }])
    expect(result.raw_metadata.fetch("documents").first).not_to include("content")
  end
end
