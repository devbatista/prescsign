require "digest"

module Documents
  class SigningService
    def initialize(actor:, request_id: nil, request_origin: nil, ip_address: nil, user_agent: nil, signature_provider: Signatures::InternalProvider.new)
      @actor = actor
      @request_id = request_id
      @request_origin = request_origin
      @ip_address = ip_address
      @user_agent = user_agent
      @signature_provider = signature_provider
      @lifecycle = Documents::LifecycleService.new(
        actor: actor,
        request_id: request_id,
        request_origin: request_origin,
        ip_address: ip_address,
        user_agent: user_agent
      )
    end

    def sign!(document:)
      raise ActiveRecord::RecordInvalid, document unless signable?(document)

      ActiveRecord::Base.transaction do
        content = document.documentable.content.to_s
        signed_at = Time.current
        signature_value = @signature_provider.sign(content: content, principal_id: @actor.id, occurred_at: signed_at)

        @lifecycle.append_version_from_content!(document: document, content: content)

        document.update!(
          status: "sent",
          signed_at: signed_at,
          metadata: document.metadata.merge(
            "signature" => {
              "value" => signature_value,
              "method" => "internal_mvp",
              "provider_version" => Signatures::InternalProvider::VERSION,
              "signed_by_user_id" => @actor.id,
              "signed_at" => signed_at.iso8601,
              "signed_content_checksum" => Digest::SHA256.hexdigest(content),
              "signed_version" => document.current_version
            }
          )
        )

        before_status = document.documentable.status
        document.documentable.update!(status: "signed")

        @lifecycle.log_updated!(
          resource: document,
          patient: document.patient,
          document: document,
          before_data: { status: "issued", signed_at: nil },
          after_data: { status: "sent", signed_at: document.signed_at }
        )
        log_signed!(document)
        log_status_change!(resource: document, from: "issued", to: "sent")
        log_status_change!(resource: document.documentable, from: before_status, to: "signed")
      end

      document.reload
    rescue StandardError => e
      Observability::CriticalAlertService.notify!(
        category: "signature_failure",
        exception: e,
        context: {
          document_id: document.id,
          user_id: @actor&.id,
          request_id: @request_id,
          request_origin: @request_origin,
          ip_address: @ip_address
        }
      )
      raise
    end

    private

    def signable?(document)
      document.status == "issued" && document.documentable.status == "draft"
    end

    def log_signed!(document)
      AuditLog.record!(
        actor: @actor,
        organization: document.organization,
        patient: document.patient,
        document: document,
        resource: document,
        action: "signed",
        occurred_at: Time.current,
        before_data: {},
        after_data: document.metadata.fetch("signature", {}),
        request_id: @request_id,
        request_origin: @request_origin,
        ip_address: @ip_address,
        user_agent: @user_agent
      )
    end

    def log_status_change!(resource:, from:, to:)
      doc = resource.is_a?(Document) ? resource : resource.document
      AuditLog.record!(
        actor: @actor,
        organization: doc.organization,
        patient: resource.patient,
        document: doc,
        resource: resource,
        action: "status_changed",
        occurred_at: Time.current,
        before_data: { status: from },
        after_data: { status: to },
        request_id: @request_id,
        request_origin: @request_origin,
        ip_address: @ip_address,
        user_agent: @user_agent
      )
    end
  end
end
