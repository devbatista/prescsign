require "digest"

module Documents
  class IntegrityService
    def initialize(actor:, request_id: nil, request_origin: nil, ip_address: nil, user_agent: nil)
      @actor = actor
      @request_id = request_id
      @request_origin = request_origin
      @ip_address = ip_address
      @user_agent = user_agent
      @lifecycle = Documents::LifecycleService.new(
        actor: actor,
        request_id: request_id,
        request_origin: request_origin,
        ip_address: ip_address,
        user_agent: user_agent
      )
    end

    def verify!(document:)
      signature_meta = document.metadata.fetch("signature", {})
      verification = verify_signature_checksum(document, signature_meta)

      return { valid: true, document: document } if verification.fetch(:valid)

      ActiveRecord::Base.transaction do
        before_status = document.status
        resource_before_status = document.documentable.status
        document.update!(status: "revoked", cancelled_at: Time.current)
        document.documentable.update!(status: "cancelled")

        @lifecycle.log_updated!(
          resource: document,
          patient: document.patient,
          document: document,
          before_data: { integrity: "valid" },
          after_data: { integrity: "invalid" }
        )

        AuditLog.record!(
          actor: @actor,
          organization: document.organization,
          patient: document.patient,
          document: document,
          resource: document,
          action: "status_changed",
          occurred_at: Time.current,
          before_data: { status: before_status },
          after_data: { status: "revoked" },
          request_id: @request_id,
          request_origin: @request_origin,
          ip_address: @ip_address,
          user_agent: @user_agent
        )
        AuditLog.record!(
          actor: @actor,
          organization: document.organization,
          patient: document.patient,
          document: document,
          resource: document.documentable,
          action: "status_changed",
          occurred_at: Time.current,
          before_data: { status: resource_before_status },
          after_data: { status: "cancelled" },
          request_id: @request_id,
          request_origin: @request_origin,
          ip_address: @ip_address,
          user_agent: @user_agent
        )
        AuditLog.record!(
          actor: @actor,
          organization: document.organization,
          patient: document.patient,
          document: document,
          resource: document,
          action: "revoked",
          occurred_at: Time.current,
          before_data: {},
          after_data: verification.except(:valid).merge(reason: "integrity_mismatch"),
          request_id: @request_id,
          request_origin: @request_origin,
          ip_address: @ip_address,
          user_agent: @user_agent
        )
      end

      { valid: false, document: document.reload }
    end

    private

    def verify_signature_checksum(document, signature_meta)
      if signature_meta["method"] == "internal_mvp" && signature_meta["signed_content_checksum"].present?
        return verify_content_checksum(document, signature_meta["signed_content_checksum"].to_s)
      end

      if signature_meta["signed_pdf_checksum"].present?
        return verify_pdf_checksum(document, signature_meta)
      end

      verify_content_checksum(document, signature_meta["signed_content_checksum"].to_s)
    end

    def verify_content_checksum(document, signed_checksum)
      current_checksum = Digest::SHA256.hexdigest(document.documentable.content.to_s)
      {
        valid: checksum_matches?(signed_checksum, current_checksum),
        signed_checksum: signed_checksum,
        current_checksum: current_checksum,
        checksum_source: "content"
      }
    end

    def verify_pdf_checksum(document, signature_meta)
      signed_checksum = signature_meta["signed_pdf_checksum"].to_s
      version = document.document_versions.find_by(version_number: signature_meta["signed_version"])
      current_checksum = version&.pdf_file&.attached? ? Digest::SHA256.hexdigest(version.pdf_file.download) : ""

      {
        valid: checksum_matches?(signed_checksum, current_checksum),
        signed_checksum: signed_checksum,
        current_checksum: current_checksum,
        checksum_source: "pdf"
      }
    end

    def checksum_matches?(signed_checksum, current_checksum)
      signed_checksum.present? &&
        current_checksum.present? &&
        ActiveSupport::SecurityUtils.secure_compare(signed_checksum, current_checksum)
    end
  end
end
