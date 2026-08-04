require "digest"
require "stringio"

module Documents
  class IntegrityService
    # Código de negócio do verify da EVAL que É prova de adulteração: resumo
    # criptográfico incorreto. O -309 ("lista de assinaturas vazia") NÃO prova
    # adulteração (pode ser formato/armazenamento) e não deve destruir o documento.
    TAMPERED_CRYPTO_CODE = -725

    def initialize(actor:, request_id: nil, request_origin: nil, ip_address: nil, user_agent: nil, signature_provider: Signatures::ProviderFactory.build)
      @actor = actor
      @request_id = request_id
      @request_origin = request_origin
      @ip_address = ip_address
      @user_agent = user_agent
      @signature_provider = signature_provider
      @lifecycle = Documents::LifecycleService.new(
        actor: actor,
        request_id: request_id,
        request_origin: request_origin,
        ip_address: ip_address,
        user_agent: user_agent
      )
    end

    # Verifica a integridade e retorna um de três desfechos — NUNCA binário:
    #   :intact -> íntegro (checksum bate e, quando aplicável, a EVAL confirma)
    #   :tampered -> PROVA POSITIVA de adulteração -> revoga (irreversível)
    #   :indeterminate -> não foi possível ler/comparar o blob local (ilegível,
    #                     versão/metadado ausente) -> NÃO muda status
    #   :already_revoked -> documento já terminal; não re-julga nem afirma integridade
    #
    # Regra central: só revoga com prova positiva de adulteração. "Não consegui
    # verificar" jamais vira "revogado", porque a revogação é irreversível e tem
    # valor jurídico.
    def verify!(document:)
      # F3: já revogado — não re-verifica nem responde "integridade confirmada".
      return { status: :already_revoked, valid: false, document: document } if document.status == "revoked"

      signature_meta = document.metadata.fetch("signature", {})
      local = verify_signature_checksum(document, signature_meta)

      outcome =
        case local[:status]
        when :match
          # Blob é byte-a-byte o que assinamos: a EVAL pode julgar esses bytes.
          crypto_outcome(document, signature_meta, local)
        when :mismatch
          # Prova positiva: o armazenado difere do que foi assinado.
          { status: :tampered, detail: local }
        else
          # Não deu para ler/comparar: indeterminado, jamais revoga. (F1/F2)
          { status: :indeterminate, detail: local }
        end

      case outcome[:status]
      when :intact
        { status: :intact, valid: true, document: document }
      when :tampered
        revoke_for_integrity!(document, outcome[:detail])
        { status: :tampered, valid: false, document: document.reload }
      else
        { status: :indeterminate, valid: nil, document: document, detail: outcome[:detail] }
      end
    end

    private

    # Decide o desfecho a partir da camada criptográfica, sabendo que o checksum
    # local já bateu (blob idêntico ao assinado). A EVAL só pode CONFIRMAR ou, com
    # prova positiva (-725), reprovar; indisponibilidade/ambiguidade degrada para o
    # veredito local (íntegro) — nunca revoga por engano.
    def crypto_outcome(document, signature_meta, local)
      crypto = crypto_verify(document, signature_meta)
      return { status: :intact, detail: local } if crypto.nil? || crypto[:status] == :valid

      { status: :tampered, detail: crypto }
    end

    # Valida a assinatura na EVAL. Retorna nil (mantém o veredito local do match)
    # quando não se aplica (assinatura não-EVAL, provedor sem verify, PDF ausente)
    # ou quando o provedor está indisponível/falha — nunca revoga por indisponibilidade.
    def crypto_verify(document, signature_meta)
      return nil unless signature_meta["provider"] == Signatures::EvalCryptoCuboProvider::PROVIDER_NAME
      return nil unless @signature_provider.respond_to?(:verify_pdf!)

      version = document.document_versions.find_by(version_number: signature_meta["signed_version"])
      return nil unless version&.pdf_file&.attached?

      result = @signature_provider.verify_pdf!(document: document, pdf_io: StringIO.new(version.pdf_file.download))
      # Só produz veredito com resposta definitiva: assinatura válida, ou prova de
      # adulteração (-725). Qualquer negativo ambíguo (-309 "sem assinatura", sem
      # código, valid nil) degrada para nil -> mantém o veredito local (o checksum
      # já bateu), nunca revoga por engano.
      crypto_code = Integer(result.raw_metadata.to_h.dig("error", "code"), exception: false)
      return nil unless result.valid || crypto_code == TAMPERED_CRYPTO_CODE

      {
        status: result.valid ? :valid : :tampered,
        checksum_source: "eval_verify",
        crypto_validation_status: result.validation_status,
        signers: result.signatures
      }
    rescue Signatures::ProviderUnavailableError, Signatures::SignatureError
      nil
    end

    def verify_signature_checksum(document, signature_meta)
      if signature_meta["method"] == "internal_mvp" && signature_meta["signed_content_checksum"].present?
        return verify_content_checksum(document, signature_meta["signed_content_checksum"].to_s)
      end

      if signature_meta["signed_pdf_checksum"].present?
        return verify_pdf_checksum(document, signature_meta)
      end

      verify_content_checksum(document, signature_meta["signed_content_checksum"].to_s)
    end

    def verify_content_checksum(document, signed_checksum)
      current_checksum = Digest::SHA256.hexdigest(document.documentable.content.to_s)
      checksum_status(signed_checksum, current_checksum, source: "content")
    end

    def verify_pdf_checksum(document, signature_meta)
      signed_checksum = signature_meta["signed_pdf_checksum"].to_s
      version = document.document_versions.find_by(version_number: signature_meta["signed_version"])
      current_checksum = version&.pdf_file&.attached? ? Digest::SHA256.hexdigest(version.pdf_file.download) : ""

      checksum_status(signed_checksum, current_checksum, source: source_or_missing(version))
    end

    def source_or_missing(version)
      version&.pdf_file&.attached? ? "pdf" : "pdf_unavailable"
    end

    # Três estados, nunca dois:
    #   :indeterminate -> falta um dos lados (blob/metadado ausente): não conclui nada
    #   :mismatch      -> ambos presentes e DIFERENTES: prova positiva de adulteração
    #   :match         -> ambos presentes e iguais
    def checksum_status(signed_checksum, current_checksum, source:)
      base = {
        checksum_source: source,
        signed_checksum: signed_checksum.presence,
        current_checksum: current_checksum.presence
      }
      return base.merge(status: :indeterminate) if signed_checksum.blank? || current_checksum.blank?

      matches = ActiveSupport::SecurityUtils.secure_compare(signed_checksum, current_checksum)
      base.merge(status: matches ? :match : :mismatch)
    end

    def revoke_for_integrity!(document, detail)
      ActiveRecord::Base.transaction do
        before_status = document.status
        resource_before_status = document.documentable.status
        document.update!(status: "revoked", cancelled_at: Time.current)
        document.documentable.update!(status: "cancelled")

        @lifecycle.log_updated!(
          resource: document,
          patient: document.patient,
          document: document,
          before_data: { integrity: "valid" },
          after_data: { integrity: "invalid" }
        )

        AuditLog.record!(
          actor: @actor,
          organization: document.organization,
          patient: document.patient,
          document: document,
          resource: document,
          action: "status_changed",
          occurred_at: Time.current,
          before_data: { status: before_status },
          after_data: { status: "revoked" },
          request_id: @request_id,
          request_origin: @request_origin,
          ip_address: @ip_address,
          user_agent: @user_agent
        )
        AuditLog.record!(
          actor: @actor,
          organization: document.organization,
          patient: document.patient,
          document: document,
          resource: document.documentable,
          action: "status_changed",
          occurred_at: Time.current,
          before_data: { status: resource_before_status },
          after_data: { status: "cancelled" },
          request_id: @request_id,
          request_origin: @request_origin,
          ip_address: @ip_address,
          user_agent: @user_agent
        )
        AuditLog.record!(
          actor: @actor,
          organization: document.organization,
          patient: document.patient,
          document: document,
          resource: document,
          action: "revoked",
          occurred_at: Time.current,
          before_data: {},
          after_data: (detail || {}).except(:status).merge(reason: "integrity_mismatch"),
          request_id: @request_id,
          request_origin: @request_origin,
          ip_address: @ip_address,
          user_agent: @user_agent
        )
      end
    end
  end
end
