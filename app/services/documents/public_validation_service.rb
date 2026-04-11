require "rqrcode"

module Documents
  class PublicValidationService
    NON_VALID_STATUSES = %w[revoked expired].freeze

    def initialize(base_url:)
      @base_url = base_url.to_s.chomp("/")
    end

    def validation_url(document)
      "#{@base_url}/v1/public/documents/#{document.code}/validation"
    end

    def qr_svg(document)
      RQRCode::QRCode.new(validation_url(document)).as_svg(
        color: "000",
        shape_rendering: "crispEdges",
        module_size: 4,
        standalone: true,
        use_path: true
      )
    end

    def status_reason(document)
      return "revoked" if document.status == "revoked"
      return "expired" if document.status == "expired"

      nil
    end

    def valid?(document)
      !NON_VALID_STATUSES.include?(document.status)
    end

    def public_payload(document)
      {
        valid: valid?(document),
        status_reason: status_reason(document),
        document: {
          code: document.code,
          kind: document.kind,
          status: document.status,
          issued_on: document.issued_on,
          current_version: document.current_version
        },
        issuer: {
          full_name: document.doctor.full_name,
          license_number: document.doctor.license_number,
          license_state: document.doctor.license_state
        },
        validation: {
          url: validation_url(document),
          qr_code_svg: qr_svg(document)
        }
      }
    end
  end
end
