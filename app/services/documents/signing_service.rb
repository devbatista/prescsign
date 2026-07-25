require "digest"
require "stringio"

module Documents
  class SigningService
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

    def sign!(document:)
      raise ActiveRecord::RecordInvalid, document unless signable?(document)

      ActiveRecord::Base.transaction do
        # Portão SNCR: receita controlada consome um número do pool do prescritor
        # aqui (atômico com a assinatura). Sem saldo -> PoolEmpty faz rollback e
        # nada é assinado. No-op para documentos comuns.
        Sncr::NumberingAssignment.ensure_for!(document.documentable)

        content = document.documentable.content.to_s
        content_checksum = Digest::SHA256.hexdigest(content)
        next_version = document.current_version + 1
        pdf = render_pdf_for_signature(document: document, version_number: next_version, checksum: content_checksum)
        signature_result = @signature_provider.sign_pdf!(
          document: document,
          pdf_io: StringIO.new(pdf),
          signer: @actor
        )
        signed_at = signature_result.signed_at || Time.current
        signed_pdf_checksum = Digest::SHA256.hexdigest(signature_result.signed_pdf)

        signed_version = DocumentVersion.create!(
          document: document,
          version_number: next_version,
          content: content,
          checksum: signed_pdf_checksum,
          generated_at: signed_at
        )
        signed_version.attach_pdf!(signature_result.signed_pdf)

        document.update!(
          status: "sent",
          current_version: next_version,
          signed_at: signed_at,
          metadata: document.metadata.merge(
            "signature" => signature_metadata(
              result: signature_result,
              signed_at: signed_at,
              signed_version: next_version,
              signed_pdf_checksum: signed_pdf_checksum
            )
          )
        )

        before_status = document.documentable.status
        document.documentable.update!(status: "signed")

        @lifecycle.log_updated!(
          resource: document,
          patient: document.patient,
          document: document,
          before_data: { status: "issued", signed_at: nil },
          after_data: { status: "sent", signed_at: document.signed_at }
        )
        log_signed!(document)
        log_status_change!(resource: document, from: "issued", to: "sent")
        log_status_change!(resource: document.documentable, from: before_status, to: "signed")
      end

      document.reload
    rescue SncrNumbering::PoolEmpty, Sncr::Error
      # Condições de negócio esperadas do portão SNCR (sem saldo de numeração /
      # prescritor sem perfil): não são falha de assinatura. Como `ensure_for!`
      # roda no topo da transação, nada foi assinado — apenas propaga para o
      # controller redirecionar, sem disparar alerta crítico.
      raise
    rescue StandardError => e
      Observability::CriticalAlertService.notify!(
        category: "signature_failure",
        exception: e,
        context: {
          document_id: document.id,
          user_id: @actor&.id,
          request_id: @request_id,
          request_origin: @request_origin,
          ip_address: @ip_address
        }
      )
      raise
    end

    private

    def signable?(document)
      document.status == "issued" && document.documentable.status == "draft"
    end

    def render_pdf_for_signature(document:, version_number:, checksum:)
      Documents::PdfRenderer.new(
        document: document,
        base_url: @request_origin,
        version_number: version_number,
        checksum: checksum,
        signer: @actor
      ).render
    end

    def signature_metadata(result:, signed_at:, signed_version:, signed_pdf_checksum:)
      result.raw_metadata.to_h.merge(
        "method" => result.method,
        "provider" => result.provider,
        "policy" => result.policy,
        "certificate_subject" => result.certificate_subject,
        "certificate_issuer" => result.certificate_issuer,
        "certificate_serial" => result.certificate_serial,
        "certificate_cpf" => result.certificate_cpf,
        "signed_by_user_id" => @actor.id,
        "signed_at" => signed_at.iso8601,
        "timestamped" => result.timestamped,
        "validation_status" => result.validation_status,
        "signed_version" => signed_version,
        "signed_pdf_checksum" => signed_pdf_checksum
      ).compact
    end

    def log_signed!(document)
      AuditLog.record!(
        actor: @actor,
        organization: document.organization,
        patient: document.patient,
        document: document,
        resource: document,
        action: "signed",
        occurred_at: Time.current,
        before_data: {},
        after_data: document.metadata.fetch("signature", {}),
        request_id: @request_id,
        request_origin: @request_origin,
        ip_address: @ip_address,
        user_agent: @user_agent
      )
    end

    def log_status_change!(resource:, from:, to:)
      doc = resource.is_a?(Document) ? resource : resource.document
      AuditLog.record!(
        actor: @actor,
        organization: doc.organization,
        patient: resource.patient,
        document: doc,
        resource: resource,
        action: "status_changed",
        occurred_at: Time.current,
        before_data: { status: from },
        after_data: { status: to },
        request_id: @request_id,
        request_origin: @request_origin,
        ip_address: @ip_address,
        user_agent: @user_agent
      )
    end
  end
end
