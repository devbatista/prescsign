module V1
  module Public
    class DocumentValidationsController < ApplicationController
      def show
        document = Document.includes(:doctor, :patient, :organization).find_by(code: params[:code].to_s.strip.upcase)
        return render_not_found if document.nil?

        lifecycle_service.log_viewed!(
          resource: document,
          patient: document.patient,
          document: document,
          details: { context: "public_document_validation" }
        )

        render_success(data: public_validation_service.public_payload(document))
      end

      private

      def render_not_found
        render_error("Document not found", status: :not_found, meta: { valid: false })
      end

      def public_validation_service
        @public_validation_service ||= Documents::PublicValidationService.new(base_url: request.base_url)
      end

      def lifecycle_service
        @lifecycle_service ||= Documents::LifecycleService.new(
          request_id: request.request_id,
          request_origin: request.base_url,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
      end
    end
  end
end
