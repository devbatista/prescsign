module App
  # Document hub within the panel (app.prescsign.local). Mirrors
  # V1::DocumentsController, reusing DocumentPolicy and the signing / integrity
  # services. This is where a document is signed, integrity-checked and resent.
  class DocumentsController < ApplicationController
    before_action :ensure_active_organization!
    before_action :set_document, except: %i[index]

    # Reenvio pelo painel é ação deliberada de uma pessoa: a idempotência aqui
    # serve para descartar duplo-clique, não para proibir que o médico reenvie
    # a quem perdeu o email. Daí a janela curta na chave — ao contrário da
    # entrega automática ao assinar, que usa chave fixa e precisa ser única.
    RESEND_DEDUPE_WINDOW = 1.minute

    def index
      authorize Document
      documents = policy_scope(Document).includes(:patient, :organization, :documentable).order(created_at: :desc)
      @prescription_documents, @prescriptions_page, @prescriptions_total_pages, @prescriptions_total =
        paginate(documents.where(kind: "prescription"), per_page: 10, page_param: :prescriptions_page)
      @medical_certificate_documents, @medical_certificates_page, @medical_certificates_total_pages, @medical_certificates_total =
        paginate(documents.where(kind: "medical_certificate"), per_page: 10, page_param: :medical_certificates_page)
    end

    def show
      authorize @document
      lifecycle_service.log_viewed!(
        resource: @document, patient: @document.patient, document: @document,
        details: { context: "documents_show" }
      )
      @documentable = @document.documentable
      @last_delivery = @document.delivery_logs.where(status: %w[sent delivered]).order(:attempted_at).last
      # A interface só oferece canal que entrega de fato — a lista vem dos
      # adapters, não de uma cópia estática que envelhece em silêncio.
      # `kind` diz ao formulário o que o campo de destinatário aceita — e-mail ou
      # telefone — sem que o JS precise reconhecer nomes de canal.
      @delivery_channels = Deliveries::AdapterFactory.available_channels.map do |channel|
        { value: channel, label: DeliveryLog::CHANNEL_LABELS.fetch(channel, channel),
          kind: recipient_kind(channel) }
      end
      versions = @document.document_versions.order(version_number: :desc)
      @versions, @versions_page, @versions_total_pages, @versions_total =
        paginate(versions, per_page: 10, page_param: :versions_page)
    end

    def sign
      authorize @document, :sign?
      signing_service(signing_pin: params[:pin]).sign!(document: @document)
      redirect_to document_path(@document), notice: "Documento assinado com sucesso."
    # Uma mensagem por categoria de falha: o que o médico deve fazer muda em cada
    # uma — e no certificado bloqueado a orientação é justamente NÃO repetir.
    # Ordem importa: todas descendem de SignatureError, que fica por último.
    rescue Signatures::ProviderUnavailableError
      redirect_to document_path(@document),
                  alert: "Serviço de assinatura temporariamente indisponível. Tente novamente em instantes."
    rescue Signatures::CertificateBlockedError
      redirect_to document_path(@document),
                  alert: "Certificado bloqueado pela certificadora após tentativas com PIN incorreto. " \
                         "Novas tentativas não resolvem — o desbloqueio é feito junto à EVAL. Nosso time já foi avisado."
    rescue Signatures::ProviderConfigurationError
      redirect_to document_path(@document),
                  alert: "Assinatura indisponível por um problema de configuração da integração. " \
                         "Nosso time já foi avisado — não é preciso tentar novamente."
    rescue Signatures::SignerCredentialError
      redirect_to document_path(@document),
                  alert: "PIN do certificado incorreto. Atenção: tentativas repetidas com o PIN errado bloqueiam o certificado."
    rescue Signatures::SignatureError
      redirect_to document_path(@document),
                  alert: "Não foi possível assinar o documento. Verifique o PIN e, se o erro persistir, contate o suporte."
    rescue SncrNumbering::PoolEmpty
      redirect_to sncr_numberings_path,
                  alert: "Sem numeração SNCR disponível para este tipo de receita. Solicite um novo lote antes de assinar."
    rescue ::Sncr::Error => e
      # Documents::SigningService deixa Sncr::Error passar sem alerta crítico
      # (condição esperada do portão de numeração); aqui só registramos e
      # traduzimos, sem expor a resposta crua da Anvisa ao médico.
      redirect_to document_path(@document),
                  alert: report_sncr_error(
                    e,
                    category: "sncr_numbering_assignment",
                    alert: "Não foi possível obter a numeração SNCR para este documento. " \
                           "Tente novamente; se o erro persistir, contate o suporte.",
                    notify: false,
                    document_id: @document.id
                  )
    rescue ActiveRecord::RecordInvalid => e
      redirect_to document_path(@document), alert: e.record.errors.full_messages.presence&.to_sentence || "Documento não pode ser assinado."
    end

    def integrity_check
      authorize @document, :integrity_check?
      result = integrity_service.verify!(document: @document)
      case result.fetch(:status)
      when :intact
        redirect_to document_path(@document), notice: "Integridade confirmada."
      when :tampered
        redirect_to document_path(@document), alert: "Integridade inválida — documento revogado."
      when :already_revoked
        redirect_to document_path(@document), alert: "Documento já revogado."
      else # :indeterminate
        redirect_to document_path(@document),
                    alert: "Não foi possível verificar a integridade agora. Tente novamente em instantes."
      end
    end

    def resend
      authorize @document, :resend?

      channel = params[:channel].to_s.strip.downcase
      unless DeliveryLog::CHANNELS.include?(channel)
        return redirect_to document_path(@document), alert: "Canal de envio não suportado."
      end

      # Canal conhecido pelo modelo não é canal entregável: SMS e WhatsApp não
      # têm provedor. Barrar aqui dá resposta imediata ao médico e evita
      # enfileirar um job que só pode falhar — e acionar alerta crítico.
      unless Deliveries::AdapterFactory.available?(channel)
        return redirect_to document_path(@document),
                           alert: "Canal indisponível no momento. Envie o documento por e-mail."
      end

      recipient = resolved_recipient(channel)
      if recipient.blank?
        return redirect_to document_path(@document), alert: "Informe o destinatário para o canal selecionado."
      end

      # Destinatário fora do formato do canal só falharia no provedor, depois do
      # job — e um número incompleto entregaria o documento a outra pessoa.
      unless recipient_matches_channel?(channel: channel, recipient: recipient)
        return redirect_to document_path(@document), alert: invalid_recipient_alert(channel)
      end

      DocumentChannelDeliveryJob.perform_later(
        document_id: @document.id,
        channel: channel,
        recipient: recipient,
        user_id: current_user.id,
        patient_id: @document.patient_id,
        request_id: request.request_id,
        idempotency_key: resend_idempotency_key(channel: channel, recipient: recipient),
        metadata: { "trigger" => "documents_resend_panel" }
      )

      redirect_to document_path(@document), notice: "Envio solicitado via #{channel} para #{recipient}."
    end

    private

    def resend_idempotency_key(channel:, recipient:)
      window = Time.current.to_i / RESEND_DEDUPE_WINDOW.to_i
      "document:#{@document.id}:channel:#{channel}:recipient:#{recipient}:window:#{window}"
    end

    def set_document
      @document = policy_scope(Document)
                  .includes(:patient, :organization, :documentable, :document_versions)
                  .find(params[:id])
    end

    def recipient_kind(channel)
      channel == "email" ? "email" : "phone"
    end

    def recipient_matches_channel?(channel:, recipient:)
      if recipient_kind(channel) == "email"
        recipient.match?(URI::MailTo::EMAIL_REGEXP)
      else
        Deliveries::PhoneNumber.to_e164(recipient).present?
      end
    end

    def invalid_recipient_alert(channel)
      if recipient_kind(channel) == "email"
        "Informe um e-mail válido para o envio."
      else
        "Informe um número de WhatsApp válido, com DDD."
      end
    end

    def resolved_recipient(channel)
      explicit = params[:recipient].to_s.strip
      return explicit if explicit.present?

      channel == "email" ? @document.patient&.email.to_s.strip : @document.patient&.phone.to_s.strip
    end

    def signing_service(signing_pin: nil)
      Documents::SigningService.new(actor: current_user, signing_pin: signing_pin, **audit_context)
    end

    def integrity_service
      @integrity_service ||= Documents::IntegrityService.new(actor: current_user, **audit_context)
    end

    def lifecycle_service
      @lifecycle_service ||= Documents::LifecycleService.new(actor: current_user, **audit_context)
    end

    def audit_context
      {
        request_id: request.request_id,
        request_origin: request.base_url,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      }
    end
  end
end
