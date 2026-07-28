require "rails_helper"
require "base64"

RSpec.describe Signatures::EvalCryptoCuboProvider do
  let(:document) { instance_double(Document, id: "doc-1", code: "ABC12345") }
  let(:user) { instance_double(User, id: 42) }

  it "fails fast when signing configuration is missing" do
    provider = described_class.new(base_url: nil, api_key: nil, profile: nil, alias_name: nil, pin: nil)

    expect do
      provider.sign_pdf!(document: document, pdf_io: StringIO.new("%PDF"), signer: user)
    end.to raise_error(Signatures::SignatureError, /base URL/)
  end

  it "uses the v0 qualified sign path and profile/icpbr query" do
    provider = described_class.new(
      base_url: "https://api.example",
      api_key: "sub-key",
      profile: "adrb",
      icpbr: "false"
    )

    expect(provider.send(:sign_path)).to eq("/api/eletronic-signatures/v0/sign/qualified/pdf")
    expect(provider.send(:sign_query)).to eq(profile: "adrb", icpbr: "false")
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

  it "builds the v0 signing payload with the PIN Base64-encoded" do
    provider = described_class.new(base_url: "https://api.example", api_key: "sub-key", profile: "adrb", format: "detached")

    payload = provider.send(:signature_payload, pdf_binary: "%PDF", signer_alias: "39932899860", signer_pin: "12345678")

    expect(payload).to eq(
      format: "detached",
      alias: "39932899860",
      pin: Base64.strict_encode64("12345678"),
      documents: [{ content: Base64.strict_encode64("%PDF") }]
    )
  end

  it "uses the signer's DoctorProfile CPF as alias, falling back to the config alias" do
    provider = described_class.new(
      base_url: "https://api.example", api_key: "sub-key", profile: "adrb",
      alias_name: "config-cpf", use_config_alias: "false"
    )
    doctor_signer = instance_double(User, doctor_profile: instance_double(DoctorProfile, cpf: "39932899860"))

    expect(provider.send(:effective_alias, doctor_signer)).to eq("39932899860")
    expect(provider.send(:effective_alias, nil)).to eq("config-cpf")
  end

  it "forces the config alias when use_config_alias is set (homologação em modo produção)" do
    provider = described_class.new(
      base_url: "https://api.example", api_key: "sub-key", profile: "adrb",
      alias_name: "config-cpf", use_config_alias: "true"
    )
    doctor_signer = instance_double(User, doctor_profile: instance_double(DoctorProfile, cpf: "39932899860"))

    expect(provider.send(:effective_alias, doctor_signer)).to eq("config-cpf")
  end

  it "forces the config alias in development regardless of the signer" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
    provider = described_class.new(
      base_url: "https://api.example", api_key: "sub-key", profile: "adrb",
      alias_name: "config-cpf", use_config_alias: "false"
    )
    doctor_signer = instance_double(User, doctor_profile: instance_double(DoctorProfile, cpf: "39932899860"))

    expect(provider.send(:effective_alias, doctor_signer)).to eq("config-cpf")
  end

  it "raises when no signing PIN is available (per-call nor config)" do
    provider = described_class.new(base_url: "https://api.example", api_key: "sub-key", profile: "adrb", alias_name: "cpf", pin: nil)

    expect do
      provider.sign_pdf!(document: document, pdf_io: StringIO.new("%PDF"), signer: nil, pin: nil)
    end.to raise_error(Signatures::SignatureError, /PIN/)
  end

  context "provider HTTP errors" do
    let(:provider) do
      described_class.new(base_url: "https://api.example", api_key: "k", profile: "adrb",
                          alias_name: "cpf", pin: "1234", use_config_alias: "false")
    end

    def stub_response(response)
      allow(response).to receive(:body).and_return('{"error":{"code":"x","message":"y"}}')
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(response)
    end

    it "maps a 5xx (gateway/unavailable) to ProviderUnavailableError" do
      stub_response(Net::HTTPGatewayTimeout.new("1.1", "504", "Gateway Timeout"))

      expect do
        provider.sign_pdf!(document: document, pdf_io: StringIO.new("%PDF"), signer: nil, pin: "1234")
      end.to raise_error(Signatures::ProviderUnavailableError)
    end

    it "maps a 4xx to a plain SignatureError (credential/validation)" do
      stub_response(Net::HTTPBadRequest.new("1.1", "400", "Bad Request"))

      expect do
        provider.sign_pdf!(document: document, pdf_io: StringIO.new("%PDF"), signer: nil, pin: "1234")
      end.to raise_error(Signatures::SignatureError) { |e| expect(e).not_to be_a(Signatures::ProviderUnavailableError) }
    end
  end

  it "maps a v0 signing response (signatures[].value) into a signature result" do
    provider = described_class.new(base_url: "https://api.example", api_key: "sub-key", profile: "adrb")
    signed_pdf = "%PDF signed"

    result = provider.send(
      :build_signature_result,
      {
        "documents" => [
          {
            "signatures" => [
              {
                "value" => Base64.strict_encode64(signed_pdf),
                "signatureName" => "Assinatura 1",
                "signatureTime" => "2026-05-13T12:00:00Z"
              }
            ]
          }
        ],
        "validationStatus" => "valid"
      }
    )

    expect(result.signed_pdf).to eq(signed_pdf)
    expect(result.provider).to eq("eval_crypto_cubo")
    expect(result.method).to eq("eval_crypto_cubo_pades")
    expect(result.signed_at).to eq(Time.iso8601("2026-05-13T12:00:00Z"))
    expect(result.validation_status).to eq("valid")
    # metadados não retêm o PDF Base64 (nem em signatures[].value)
    expect(result.raw_metadata.dig("document", "signatures").first).not_to include("value")
    expect(result.raw_metadata.dig("document", "signatures").first["signatureName"]).to eq("Assinatura 1")
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
