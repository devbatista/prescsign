module App
  # Document hub within the panel (app.prescsign.local). Mirrors
  # V1::DocumentsController, reusing DocumentPolicy and the signing / integrity
  # services. This is where a document is signed, integrity-checked and resent.
  class DocumentsController < WebBaseController
    before_action :ensure_active_organization!
    before_action :set_document

    def show
      authorize @document
      lifecycle_service.log_viewed!(
        resource: @document, patient: @document.patient, document: @document,
        details: { context: "documents_show" }
      )
      @documentable = @document.documentable
      @versions = @document.document_versions.order(version_number: :desc)
    end

    def sign
      authorize @document, :sign?
      signing_service.sign!(document: @document)
      redirect_to document_path(@document), notice: "Documento assinado com sucesso."
    rescue ActiveRecord::RecordInvalid => e
      redirect_to document_path(@document), alert: e.record.errors.full_messages.presence&.to_sentence || "Documento não pode ser assinado."
    end

    def integrity_check
      authorize @document, :integrity_check?
      result = integrity_service.verify!(document: @document)
      if result.fetch(:valid)
        redirect_to document_path(@document), notice: "Integridade confirmada."
      else
        redirect_to document_path(@document), alert: "Integridade inválida — documento revogado."
      end
    end

    def resend
      authorize @document, :resend?

      channel = params[:channel].to_s.strip.downcase
      unless DeliveryLog::CHANNELS.include?(channel)
        return redirect_to document_path(@document), alert: "Canal de envio não suportado."
      end

      recipient = resolved_recipient(channel)
      if recipient.blank?
        return redirect_to document_path(@document), alert: "Informe o destinatário para o canal selecionado."
      end

      DocumentChannelDeliveryJob.perform_later(
        document_id: @document.id,
        channel: channel,
        recipient: recipient,
        user_id: current_user.id,
        patient_id: @document.patient_id,
        request_id: request.request_id,
        idempotency_key: "document:#{@document.id}:channel:#{channel}:recipient:#{recipient}",
        metadata: { "trigger" => "documents_resend_panel" }
      )

      redirect_to document_path(@document), notice: "Envio solicitado via #{channel}."
    end

    private

    def set_document
      @document = policy_scope(Document)
                  .includes(:patient, :organization, :documentable, :document_versions)
                  .find(params[:id])
    end

    def resolved_recipient(channel)
      explicit = params[:recipient].to_s.strip
      return explicit if explicit.present?

      channel == "email" ? @document.patient&.email.to_s.strip : @document.patient&.phone.to_s.strip
    end

    def signing_service
      @signing_service ||= Documents::SigningService.new(actor: current_user, **audit_context)
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
