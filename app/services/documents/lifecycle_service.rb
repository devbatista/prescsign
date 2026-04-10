require "digest"

module Documents
  class LifecycleService
    def initialize(actor:, request_id: nil, request_origin: nil, ip_address: nil, user_agent: nil)
      @actor = actor
      @request_id = request_id
      @request_origin = request_origin
      @ip_address = ip_address
      @user_agent = user_agent
    end

    def create_with_initial_version!(doctor:, patient:, documentable:, kind:, issued_on:, content:)
      document = Document.create!(
        doctor: doctor,
        patient: patient,
        documentable: documentable,
        kind: kind,
        code: generate_code(Document),
        status: "issued",
        issued_on: issued_on,
        current_version: 1
      )

      checksum = checksum_for(content)
      DocumentVersion.create!(
        document: document,
        version_number: 1,
        content: content,
        checksum: checksum,
        generated_at: Time.current
      )

      log_created!(resource: documentable, patient: patient, document: document)
      log_status_change!(
        resource: documentable,
        patient: patient,
        document: document,
        from: nil,
        to: documentable.status
      )
      log_created!(resource: document, patient: patient, document: document)
      log_status_change!(resource: document, patient: patient, document: document, from: nil, to: "issued")

      document
    end

    def append_version_from_content!(document:, content:)
      checksum = checksum_for(content)
      next_version = document.current_version + 1

      DocumentVersion.create!(
        document: document,
        version_number: next_version,
        content: content,
        checksum: checksum,
        generated_at: Time.current
      )

      document.update!(current_version: next_version)
      checksum
    end

    def revoke!(documentable:, reason: nil)
      document = documentable.document
      raise ActiveRecord::RecordInvalid, documentable if document.nil?
      return if document.status == "revoked"

      before_doc_status = document.status
      before_resource_status = documentable.status

      documentable.update!(status: "cancelled")
      document.update!(status: "revoked", cancelled_at: Time.current)

      log_status_change!(
        resource: documentable,
        patient: documentable.patient,
        document: document,
        from: before_resource_status,
        to: documentable.status
      )
      log_status_change!(
        resource: document,
        patient: documentable.patient,
        document: document,
        from: before_doc_status,
        to: "revoked"
      )
      log_revoked!(resource: document, patient: documentable.patient, document: document, reason: reason)
    end

    def log_updated!(resource:, patient:, document:, before_data:, after_data:)
      AuditLog.create!(
        actor: @actor,
        patient: patient,
        document: document,
        resource: resource,
        action: "updated",
        occurred_at: Time.current,
        before_data: before_data,
        after_data: after_data,
        request_id: @request_id,
        request_origin: @request_origin,
        ip_address: @ip_address,
        user_agent: @user_agent
      )
    end

    private

    def checksum_for(content)
      Digest::SHA256.hexdigest(content.to_s)
    end

    def generate_code(model_class)
      loop do
        code = SecureRandom.alphanumeric(10).upcase
        return code unless model_class.exists?(code: code)
      end
    end

    def log_created!(resource:, patient:, document:)
      AuditLog.create!(
        actor: @actor,
        patient: patient,
        document: document,
        resource: resource,
        action: "created",
        occurred_at: Time.current,
        before_data: {},
        after_data: resource.attributes,
        request_id: @request_id,
        request_origin: @request_origin,
        ip_address: @ip_address,
        user_agent: @user_agent
      )
    end

    def log_revoked!(resource:, patient:, document:, reason:)
      AuditLog.create!(
        actor: @actor,
        patient: patient,
        document: document,
        resource: resource,
        action: "revoked",
        occurred_at: Time.current,
        before_data: {},
        after_data: reason.present? ? { reason: reason } : {},
        request_id: @request_id,
        request_origin: @request_origin,
        ip_address: @ip_address,
        user_agent: @user_agent
      )
    end

    def log_status_change!(resource:, patient:, document:, from:, to:)
      AuditLog.create!(
        actor: @actor,
        patient: patient,
        document: document,
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
