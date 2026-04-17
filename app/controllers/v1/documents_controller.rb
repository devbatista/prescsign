module V1
  class DocumentsController < ApplicationController
    before_action :authenticate_doctor!
    before_action :ensure_tenant_context!
    before_action :set_document

    def show
      authorize @document
      lifecycle_service.log_viewed!(
        resource: @document,
        patient: @document.patient,
        document: @document,
        details: { context: "documents_show" }
      )
      render_success(data: document_payload(@document))
    end

    def sign
      authorize @document, :sign?

      signed = signing_service.sign!(document: @document)
      render_success(data: document_payload(signed))
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.record.errors.full_messages.presence || ["Document is not signable"], status: :unprocessable_content)
    end

    def integrity_check
      authorize @document, :integrity_check?

      result = integrity_service.verify!(document: @document)
      render_success(data: {
        valid: result.fetch(:valid),
        document: document_payload(result.fetch(:document))
      })
    end

    def resend
      authorize @document, :resend?

      channel = resend_params.fetch(:channel).to_s.strip.downcase
      unless DeliveryLog::CHANNELS.include?(channel)
        return render_error("Unsupported channel", status: :unprocessable_content)
      end

      recipient = resolved_recipient(channel)
      if recipient.blank?
        return render_error("Recipient is required for selected channel", status: :unprocessable_content)
      end

      idempotency_key = resend_params[:idempotency_key].presence || default_idempotency_key(channel, recipient)
      metadata = resend_params[:metadata].to_h.merge("trigger" => "documents_resend_endpoint")

      DocumentChannelDeliveryJob.perform_later(
        document_id: @document.id,
        channel: channel,
        recipient: recipient,
        doctor_id: current_doctor.id,
        patient_id: @document.patient_id,
        request_id: request.request_id,
        idempotency_key: idempotency_key,
        metadata: metadata
      )

      render_success(data: {
        message: "Document resend queued",
        document_id: @document.id,
        channel: channel,
        recipient: recipient,
        idempotency_key: idempotency_key
      }, status: :accepted)
    end

    private

    def set_document
      @document = policy_scope(Document).find(params[:id])
    end

    def signing_service
      @signing_service ||= Documents::SigningService.new(
        actor: current_doctor,
        request_id: request.request_id,
        request_origin: request.base_url,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end

    def lifecycle_service
      @lifecycle_service ||= Documents::LifecycleService.new(
        actor: current_doctor,
        request_id: request.request_id,
        request_origin: request.base_url,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end

    def integrity_service
      @integrity_service ||= Documents::IntegrityService.new(
        actor: current_doctor,
        request_id: request.request_id,
        request_origin: request.base_url,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end

    def resend_params
      params.fetch(:resend, {}).permit(:channel, :recipient, :idempotency_key, metadata: {})
    end

    def resolved_recipient(channel)
      explicit = resend_params[:recipient].to_s.strip
      return explicit if explicit.present?

      patient = @document.patient
      return patient&.email.to_s.strip if channel == "email"

      patient&.phone.to_s.strip
    end

    def default_idempotency_key(channel, recipient)
      "document:#{@document.id}:channel:#{channel}:recipient:#{recipient}"
    end

    def document_payload(document)
      {
        id: document.id,
        organization_id: document.organization_id,
        unit_id: document.unit_id,
        doctor_id: document.doctor_id,
        patient_id: document.patient_id,
        code: document.code,
        kind: document.kind,
        status: document.status,
        current_version: document.current_version,
        signed_at: document.signed_at,
        cancelled_at: document.cancelled_at,
        metadata: document.metadata,
        documentable_type: document.documentable_type,
        documentable_id: document.documentable_id
      }
    end
  end
end
