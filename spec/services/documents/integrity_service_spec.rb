require "rails_helper"

RSpec.describe Documents::IntegrityService do
  include WebSpecHelpers

  let(:actor) { instance_double(User, id: 1) }
  let(:pdf_file) { double("pdf_file", attached?: true, download: "%PDF signed") }
  let(:pdf_version) { instance_double(DocumentVersion, pdf_file: pdf_file) }
  let(:versions) { double("document_versions") }
  let(:document) { instance_double(Document, document_versions: versions) }
  let(:provider) { instance_double(Signatures::EvalCryptoCuboProvider) }

  let(:eval_meta) { { "provider" => "eval_crypto_cubo", "signed_version" => 2 } }

  def service(signature_provider: provider)
    described_class.new(actor: actor, signature_provider: signature_provider)
  end

  def verification_result(valid:, status: nil, signatures: [])
    Signatures::VerificationResult.new(
      provider: "eval_crypto_cubo", valid: valid, validation_status: status, signatures: signatures
    )
  end

  before do
    allow(versions).to receive(:find_by).with(version_number: 2).and_return(pdf_version)
  end

  describe "#crypto_verify (camada criptográfica EVAL)" do
    it "confirma quando a EVAL valida a assinatura do PDF armazenado" do
      allow(provider).to receive(:verify_pdf!)
        .with(document: document, pdf_io: instance_of(StringIO))
        .and_return(verification_result(valid: true, status: "valid", signatures: [{ "signers" => [] }]))

      result = service.send(:crypto_verify, document, eval_meta)

      expect(result).to include(valid: true, checksum_source: "eval_verify", crypto_validation_status: "valid")
    end

    it "reprova quando a EVAL detecta adulteração (resumo criptográfico incorreto)" do
      allow(provider).to receive(:verify_pdf!)
        .and_return(verification_result(valid: false, status: "Resumo criptográfico da mensagem incorreto."))

      result = service.send(:crypto_verify, document, eval_meta)

      expect(result[:valid]).to be(false)
      expect(result[:crypto_validation_status]).to eq("Resumo criptográfico da mensagem incorreto.")
    end

    it "degrada (retorna nil) quando o provedor está indisponível — não revoga por 504" do
      allow(provider).to receive(:verify_pdf!).and_raise(Signatures::ProviderUnavailableError)

      expect(service.send(:crypto_verify, document, eval_meta)).to be_nil
    end

    it "degrada (retorna nil) em erro do provedor (SignatureError)" do
      allow(provider).to receive(:verify_pdf!).and_raise(Signatures::SignatureError)

      expect(service.send(:crypto_verify, document, eval_meta)).to be_nil
    end

    it "não chama a EVAL para assinaturas de outro provedor (ex.: internal)" do
      expect(provider).not_to receive(:verify_pdf!)

      expect(service.send(:crypto_verify, document, { "provider" => "internal", "signed_version" => 2 })).to be_nil
    end

    it "degrada quando o PDF assinado não está anexado à versão" do
      allow(versions).to receive(:find_by).with(version_number: 2).and_return(nil)
      expect(provider).not_to receive(:verify_pdf!)

      expect(service.send(:crypto_verify, document, eval_meta)).to be_nil
    end

    it "degrada quando o veredito da EVAL é indeterminado (valid nil)" do
      allow(provider).to receive(:verify_pdf!).and_return(verification_result(valid: nil))

      expect(service.send(:crypto_verify, document, eval_meta)).to be_nil
    end
  end

  describe "#verify! (integração da camada EVAL sobre um documento real assinado)" do
    let(:organization) { create_organization }
    let(:doctor) { create_doctor(organization: organization) }
    let(:patient) { create_patient(user: doctor, organization: organization) }

    # Assina de verdade (provider internal do ambiente de teste), depois marca a
    # assinatura como EVAL para acionar a camada criptográfica no verify!.
    def signed_eval_document
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
      Documents::SigningService.new(actor: doctor).sign!(document: prescription.document)
      document = prescription.document.reload
      document.update!(
        metadata: document.metadata.merge(
          "signature" => document.metadata.fetch("signature").merge("provider" => "eval_crypto_cubo")
        )
      )
      document
    end

    def eval_provider(verify_result: nil, error: nil)
      provider = instance_double(Signatures::EvalCryptoCuboProvider)
      if error
        allow(provider).to receive(:verify_pdf!).and_raise(error)
      else
        allow(provider).to receive(:verify_pdf!).and_return(verify_result)
      end
      provider
    end

    it "revoga o documento quando a EVAL reprova a assinatura (adulteração)" do
      document = signed_eval_document
      provider = eval_provider(verify_result: verification_result(valid: false, status: "Resumo criptográfico da mensagem incorreto."))

      result = described_class.new(actor: doctor, signature_provider: provider).verify!(document: document)

      expect(result[:valid]).to be(false)
      expect(document.reload.status).to eq("revoked")
      expect(document.documentable.reload.status).to eq("cancelled")
    end

    it "mantém válido quando a EVAL está indisponível (degradação suave, sem revogar)" do
      document = signed_eval_document
      provider = eval_provider(error: Signatures::ProviderUnavailableError)

      result = described_class.new(actor: doctor, signature_provider: provider).verify!(document: document)

      expect(result[:valid]).to be(true)
      expect(document.reload.status).to eq("sent")
    end

    it "confirma quando a EVAL valida a assinatura" do
      document = signed_eval_document
      provider = eval_provider(verify_result: verification_result(valid: true, status: "valid"))

      result = described_class.new(actor: doctor, signature_provider: provider).verify!(document: document)

      expect(result[:valid]).to be(true)
      expect(document.reload.status).to eq("sent")
    end
  end
end
