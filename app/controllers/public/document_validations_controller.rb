require "rqrcode"

module Public
  # Public (unauthenticated) document validation. Mirrors
  # V1::Public::DocumentValidationsController, reusing Documents::PublicValidationService.
  # Reachable on any host from the code/QR printed on a document.
  class DocumentValidationsController < ActionController::Base
    protect_from_forgery with: :exception
    layout "public"

    def new
      @code = params[:code].to_s.strip.upcase.presence
      redirect_to public_document_validation_path(@code) if @code
    end

    def show
      @document = Document.includes(user: :doctor_profile, patient: [], organization: [])
                          .find_by(code: params[:code].to_s.strip.upcase)
      return if @document.nil?

      @payload = validation_service.public_payload(@document)
      @qr_svg = qr_svg_for(@document)
    end

    private

    def validation_service
      @validation_service ||= Documents::PublicValidationService.new(base_url: request.base_url)
    end

    # QR pointing to this public web page (not the JSON API endpoint).
    def qr_svg_for(document)
      url = public_document_validation_url(document.code, host: request.host_with_port, protocol: request.protocol)
      RQRCode::QRCode.new(url).as_svg(
        color: "0f2942", shape_rendering: "crispEdges", module_size: 4, standalone: true, use_path: true
      )
    end
  end
end
