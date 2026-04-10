module V1
  class DocumentsController < ApplicationController
    before_action :authenticate_doctor!
    before_action :set_document

    def show
      authorize @document
      render json: document_payload(@document), status: :ok
    end

    def sign
      authorize @document, :sign?

      signed = signing_service.sign!(document: @document)
      render json: document_payload(signed), status: :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages.presence || ["Document is not signable"] }, status: :unprocessable_content
    end

    def integrity_check
      authorize @document, :integrity_check?

      result = integrity_service.verify!(document: @document)
      render json: {
        valid: result.fetch(:valid),
        document: document_payload(result.fetch(:document))
      }, status: :ok
    end

    private

    def set_document
      @document = policy_scope(Document).find(params[:id])
    end

    def signing_service
      @signing_service ||= Documents::SigningService.new(actor: current_doctor)
    end

    def integrity_service
      @integrity_service ||= Documents::IntegrityService.new(actor: current_doctor)
    end

    def document_payload(document)
      {
        id: document.id,
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
