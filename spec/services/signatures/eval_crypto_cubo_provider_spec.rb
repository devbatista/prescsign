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

  it "uses the v0 verify path/query and payload with the PDF in signatures[].value" do
    provider = described_class.new(base_url: "https://api.example", api_key: "sub-key", icpbr: "false")

    expect(described_class::VERIFY_PATH).to eq("/api/eletronic-signatures/v0/verify/qualified/pdf")
    expect(provider.send(:verify_query)).to eq(icpbr: "false")
    expect(provider.send(:verification_payload, pdf_binary: "%PDF")).to eq(
      documents: [{ signatures: [{ value: Base64.strict_encode64("%PDF") }] }]
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

    def stub_error(response, code:, message:)
      allow(response).to receive(:body).and_return({ "error" => { "code" => code, "message" => message } }.to_json)
      allow_any_instance_of(Net::HTTP).to receive(:request).and_return(response)
    end

    def sign!
      provider.sign_pdf!(document: document, pdf_io: StringIO.new("%PDF"), signer: nil, pin: "1234")
    end

    it "maps a blocked certificate (400, code -335) to CertificateBlockedError carrying the code" do
      stub_error(Net::HTTPBadRequest.new("1.1", "400", "Bad Request"),
                 code: -335, message: "Certificado bloqueado devido a tentativa de uso incorreta.")

      expect { sign! }.to raise_error(Signatures::CertificateBlockedError) do |e|
        expect(e.code).to eq(-335)
        expect(e.provider_message).to match(/Certificado bloqueado/)
      end
    end

    it "maps a nonexistent profile (400, code -734) to ProviderConfigurationError" do
      stub_error(Net::HTTPBadRequest.new("1.1", "400", "Bad Request"),
                 code: -734, message: "Política de execução não encontrada.")

      expect { sign! }.to raise_error(Signatures::ProviderConfigurationError) { |e| expect(e.code).to eq(-734) }
    end

    it "maps a 401 (invalid subscription key) to ProviderConfigurationError" do
      stub_error(Net::HTTPUnauthorized.new("1.1", "401", "Unauthorized"), code: nil, message: "Access denied")

      expect { sign! }.to raise_error(Signatures::ProviderConfigurationError)
    end

    it "maps a refused PIN to SignerCredentialError" do
      stub_error(Net::HTTPBadRequest.new("1.1", "400", "Bad Request"), code: -300, message: "PIN incorreto.")

      expect { sign! }.to raise_error(Signatures::SignerCredentialError)
    end

    it "does not classify an unknown code as a PIN problem" do
      stub_error(Net::HTTPBadRequest.new("1.1", "400", "Bad Request"), code: -999, message: "Falha desconhecida.")

      expect { sign! }.to raise_error(Signatures::SignatureError) do |e|
        expect(e).not_to be_a(Signatures::SignerCredentialError)
        expect(e).not_to be_a(Signatures::CertificateBlockedError)
        expect(e).not_to be_a(Signatures::ProviderConfigurationError)
      end
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

  context "verify v0 verdicts" do
    let(:provider) { described_class.new(base_url: "https://api.example", api_key: "sub-key", icpbr: "false") }

    def http_response(klass, code, message, body)
      response = klass.new("1.1", code, message)
      allow(response).to receive(:body).and_return(body)
      response
    end

    it "maps HTTP 200 with signers to valid, stripping the echoed PDF Base64" do
      body = {
        "documents" => [
          {
            "signatures" => [
              {
                "value" => Base64.strict_encode64("%PDF signed"),
                "signers" => [{ "subject" => "RAFAEL:39932899860", "issuer" => "E-VAL AC v4" }]
              }
            ]
          }
        ]
      }.to_json
      result = provider.send(:build_verification_result, http_response(Net::HTTPOK, "200", "OK", body))

      expect(result.valid).to be(true)
      expect(result.validation_status).to eq("valid")
      expect(result.signatures).to eq([{ "signers" => [{ "subject" => "RAFAEL:39932899860", "issuer" => "E-VAL AC v4" }] }])
      # metadados não retêm o PDF Base64 (signatures[].value)
      expect(result.raw_metadata.to_json).not_to include(Base64.strict_encode64("%PDF signed"))
    end

    it "maps a tampered PDF (400, code -725) to a valid: false verdict without raising" do
      body = { "error" => { "code" => -725, "message" => "Resumo criptográfico da mensagem incorreto." } }.to_json
      result = provider.send(:build_verification_result, http_response(Net::HTTPBadRequest, "400", "Bad Request", body))

      expect(result.valid).to be(false)
      expect(result.validation_status).to eq("Resumo criptográfico da mensagem incorreto.")
      expect(result.signatures).to eq([])
    end

    it "maps an unsigned PDF (400, code -309) to a valid: false verdict without raising" do
      body = { "error" => { "code" => -309, "message" => "Lista de assinaturas vazia" } }.to_json
      result = provider.send(:build_verification_result, http_response(Net::HTTPBadRequest, "400", "Bad Request", body))

      expect(result.valid).to be(false)
      expect(result.signatures).to eq([])
    end

    it "raises ProviderUnavailableError on a 5xx (gateway/manutenção)" do
      response = http_response(Net::HTTPGatewayTimeout, "504", "Gateway Timeout", "<html>504</html>")

      expect { provider.send(:build_verification_result, response) }
        .to raise_error(Signatures::ProviderUnavailableError)
    end

    it "raises SignatureError on an unknown 4xx (auth/credential)" do
      body = { "error" => { "code" => "401", "message" => "Unauthorized" } }.to_json
      response = http_response(Net::HTTPUnauthorized, "401", "Unauthorized", body)

      expect { provider.send(:build_verification_result, response) }
        .to raise_error(Signatures::SignatureError) { |e| expect(e).not_to be_a(Signatures::ProviderUnavailableError) }
    end
  end
end
