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
      signed_checksum = signature_meta["signed_content_checksum"].to_s
      current_checksum = Digest::SHA256.hexdigest(document.documentable.content.to_s)
      valid = signed_checksum.present? && ActiveSupport::SecurityUtils.secure_compare(signed_checksum, current_checksum)

      return { valid: true, document: document } if valid

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
          after_data: { reason: "integrity_mismatch", signed_checksum: signed_checksum, current_checksum: current_checksum },
          request_id: @request_id,
          request_origin: @request_origin,
          ip_address: @ip_address,
          user_agent: @user_agent
        )
      end

      { valid: false, document: document.reload }
    end
  end
end
