module V1
  module Public
    class DocumentValidationsController < ActionController::API
      def show
        document = Document.includes(:doctor).find_by(code: params[:code].to_s.strip.upcase)
        return render_not_found if document.nil?

        render json: public_validation_service.public_payload(document), status: :ok
      end

      private

      def render_not_found
        render json: { valid: false, error: "Document not found" }, status: :not_found
      end

      def public_validation_service
        @public_validation_service ||= Documents::PublicValidationService.new(base_url: request.base_url)
      end
    end
  end
end
