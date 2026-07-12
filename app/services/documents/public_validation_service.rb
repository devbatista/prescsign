require "rqrcode"

module Documents
  class PublicValidationService
    NON_VALID_STATUSES = %w[revoked expired].freeze

    def initialize(base_url:)
      @base_url = base_url.to_s.chomp("/")
    end

    def validation_url(document)
      "#{@base_url}/validate/#{document.code}"
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
      profile = document.user&.doctor_profile
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
          full_name: profile&.full_name,
          license_number: profile&.license_number,
          license_state: profile&.license_state
        },
        signature: signature_payload(document),
        validation: {
          url: validation_url(document),
          qr_code_svg: qr_svg(document)
        }
      }
    end

    private

    def signature_payload(document)
      signature = document.metadata.fetch("signature", {})
      return nil if signature.blank?

      {
        method: signature["method"],
        provider: signature["provider"],
        policy: signature["policy"],
        signed_at: signature["signed_at"],
        timestamped: signature["timestamped"],
        validation_status: signature["validation_status"],
        signed_version: signature["signed_version"],
        signed_pdf_checksum: signature["signed_pdf_checksum"]
      }.compact
    end
  end
end
