require "timeout"

module Documents
  class PdfRenderer
    RenderVersion = Data.define(:version_number, :checksum)

    def initialize(document:, base_url:, version_number: nil, checksum: nil)
      @document = document
      @base_url = base_url
      @version_number = version_number
      @checksum = checksum
    end

    def render
      Timeout.timeout(pdf_generation_timeout_seconds) do
        WickedPdf.new.pdf_from_string(
          html,
          page_size: "A4",
          margin: { top: 12, right: 10, bottom: 12, left: 10 },
          encoding: "UTF-8"
        )
      end
    end

    private

    attr_reader :document, :base_url, :version_number, :checksum

    def html
      ActionController::Base.renderer.render(
        template: template,
        layout: "pdf",
        locals: locals
      )
    end

    def template
      case document.kind
      when "prescription"
        "v1/prescriptions/pdf"
      when "medical_certificate"
        "v1/medical_certificates/pdf"
      else
        raise ArgumentError, "Unsupported document kind: #{document.kind.inspect}"
      end
    end

    def locals
      {
        documentable_key => document.documentable,
        doctor: document.user.doctor_profile,
        patient: document.patient,
        document: document_for_render,
        latest_version: version_for_render,
        validation_url: public_validation_service.validation_url(document),
        validation_qr_svg: public_validation_service.qr_svg(document)
      }
    end

    def documentable_key
      case document.kind
      when "prescription"
        :prescription
      when "medical_certificate"
        :medical_certificate
      end
    end

    def document_for_render
      return document if version_number.blank?

      document.dup.tap do |copy|
        copy.id = document.id
        copy.current_version = version_number
      end
    end

    def version_for_render
      return persisted_current_version if version_number.blank?

      RenderVersion.new(version_number: version_number, checksum: checksum)
    end

    def persisted_current_version
      document.document_versions.find_by!(version_number: document.current_version)
    end

    def public_validation_service
      @public_validation_service ||= Documents::PublicValidationService.new(base_url: base_url)
    end

    def pdf_generation_timeout_seconds
      configured = Rails.application.config.x.pdf_generation_timeout_seconds.to_f
      configured.positive? ? configured : 20.0
    end
  end
end
