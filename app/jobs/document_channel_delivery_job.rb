class DocumentChannelDeliveryJob < NotificationJob
  RETRY_ATTEMPTS = 5
  RETRY_BACKOFF_BASE_SECONDS = 5
  RETRY_BACKOFF_MAX_SECONDS = 300

  discard_on ArgumentError
  discard_on ActiveRecord::RecordNotFound
  discard_on Deliveries::PermanentProviderError

  retry_on Deliveries::TimeoutError,
           Deliveries::TransientProviderError,
           Deliveries::UnexpectedProviderResponseError,
           wait: ->(executions) { retry_backoff_for(executions).seconds },
           attempts: RETRY_ATTEMPTS

  def self.retry_backoff_for(executions)
    exponent = [executions.to_i - 1, 0].max
    [RETRY_BACKOFF_BASE_SECONDS * (2**exponent), RETRY_BACKOFF_MAX_SECONDS].min
  end

  def perform(document_id:, channel:, recipient:, doctor_id: nil, patient_id: nil, request_id: nil, idempotency_key: nil, metadata: {})
    document = Document.find(document_id)
    normalized_channel = channel.to_s.strip.downcase
    normalized_recipient = recipient.to_s.strip

    raise ArgumentError, "Unsupported channel: #{channel}" unless DeliveryLog::CHANNELS.include?(normalized_channel)
    raise ArgumentError, "Recipient is required" if normalized_recipient.blank?

    delivery_log = find_or_initialize_delivery_log(
      document: document,
      channel: normalized_channel,
      recipient: normalized_recipient,
      doctor_id: doctor_id,
      patient_id: patient_id,
      request_id: request_id,
      idempotency_key: idempotency_key,
      metadata: metadata
    )
    delivery_log = persist_with_idempotency!(delivery_log)

    return unless acquire_delivery_attempt!(delivery_log, metadata)

    dispatch_result = Deliveries::ChannelDispatcher.new(
      document: document,
      channel: normalized_channel,
      recipient: normalized_recipient,
      metadata: metadata
    ).call

    mark_sent!(delivery_log, dispatch_result)
  rescue StandardError => e
    mark_failed!(delivery_log, e, metadata) if defined?(delivery_log) && delivery_log.present?
    Observability::CriticalAlertService.notify!(
      category: "delivery_failure",
      exception: e,
      context: {
        job: self.class.name,
        document_id: defined?(document) && document.present? ? document.id : document_id,
        channel: defined?(normalized_channel) && normalized_channel.present? ? normalized_channel : channel,
        recipient: defined?(normalized_recipient) && normalized_recipient.present? ? normalized_recipient : recipient,
        request_id: request_id,
        idempotency_key: idempotency_key
      }
    )
    raise
  end

  private

  def find_or_initialize_delivery_log(document:, channel:, recipient:, doctor_id:, patient_id:, request_id:, idempotency_key:, metadata:)
    log = if idempotency_key.present?
            DeliveryLog.where(idempotency_key: idempotency_key).first_or_initialize
          else
            DeliveryLog.new
          end

    validate_idempotency_key_consistency!(log, channel: channel, recipient: recipient) if idempotency_key.present?
    log.document_id ||= document.id
    log.channel = channel
    log.recipient = recipient
    log.doctor_id ||= doctor_id || document.doctor_id
    log.patient_id ||= patient_id || document.patient_id
    log.request_id ||= request_id
    log.idempotency_key ||= idempotency_key
    log.status ||= "queued"
    log.attempt_number ||= 1
    log.attempted_at ||= Time.current
    log.metadata = log.metadata.merge(metadata.to_h)
    log
  end

  def already_processed?(delivery_log)
    delivery_log.persisted? && delivery_log.status.in?(%w[processing sent delivered])
  end

  def acquire_delivery_attempt!(delivery_log, metadata)
    acquired = false
    delivery_log.with_lock do
      break if already_processed?(delivery_log)

      mark_processing!(delivery_log, metadata)
      acquired = true
    end

    acquired
  end

  def persist_with_idempotency!(delivery_log)
    return delivery_log if delivery_log.persisted?

    delivery_log.save!
    delivery_log
  rescue ActiveRecord::RecordNotUnique
    raise if delivery_log.idempotency_key.blank?

    existing_log = DeliveryLog.find_by!(idempotency_key: delivery_log.idempotency_key)
    validate_idempotency_key_consistency!(existing_log, channel: delivery_log.channel, recipient: delivery_log.recipient)
    existing_log
  end

  def mark_processing!(delivery_log, metadata)
    next_attempt_number =
      if delivery_log.persisted? && delivery_log.status != "queued"
        delivery_log.attempt_number + 1
      else
        delivery_log.attempt_number.presence || 1
      end

    merged_metadata = delivery_log.metadata.merge(metadata.to_h)
    merged_metadata = append_attempt_event(
      merged_metadata,
      status: "processing",
      channel: delivery_log.channel,
      external_response: { stage: "dispatch_started" }
    )

    delivery_log.update!(
      status: "processing",
      attempted_at: Time.current,
      attempt_number: next_attempt_number,
      error_code: nil,
      error_message: nil,
      metadata: merged_metadata
    )
  end

  def mark_sent!(delivery_log, dispatch_result)
    status = dispatch_result.fetch(:status, "sent")
    delivered_at = status == "delivered" ? Time.current : nil
    external_response = {
      provider_name: dispatch_result[:provider_name],
      provider_message_id: dispatch_result[:provider_message_id],
      payload: dispatch_result.fetch(:metadata, {})
    }.compact
    merged_metadata = delivery_log.metadata.merge(dispatch_result.fetch(:metadata, {}))
    merged_metadata = append_attempt_event(
      merged_metadata,
      status: status,
      channel: delivery_log.channel,
      external_response: external_response
    )

    delivery_log.update!(
      status: status,
      provider_name: dispatch_result[:provider_name],
      provider_message_id: dispatch_result[:provider_message_id],
      delivered_at: delivered_at,
      attempted_at: Time.current,
      metadata: merged_metadata
    )

    lifecycle_service_for(delivery_log).log_sent!(
      resource: delivery_log.document,
      patient: delivery_log.patient || delivery_log.document.patient,
      document: delivery_log.document,
      details: {
        channel: delivery_log.channel,
        status: status,
        provider_name: dispatch_result[:provider_name],
        provider_message_id: dispatch_result[:provider_message_id],
        recipient: delivery_log.recipient
      }.compact
    )
  end

  def mark_failed!(delivery_log, error, metadata)
    merged_metadata = delivery_log.metadata.merge(metadata.to_h)
    merged_metadata = append_attempt_event(
      merged_metadata,
      status: "failed",
      channel: delivery_log.channel,
      external_response: {
        error_class: error.class.name,
        error_message: error.message.to_s.truncate(500)
      }
    )

    delivery_log.update!(
      status: "failed",
      error_code: error.class.name,
      error_message: error.message.to_s.truncate(2000),
      attempted_at: Time.current,
      metadata: merged_metadata
    )
  rescue StandardError
    # Never mask the original delivery error.
    nil
  end

  def append_attempt_event(metadata, status:, channel:, external_response:)
    attempts = Array(metadata["attempts"])
    attempts << {
      "status" => status,
      "channel" => channel,
      "external_response" => external_response,
      "timestamp" => Time.current.iso8601
    }
    metadata.merge("attempts" => attempts)
  end

  def validate_idempotency_key_consistency!(delivery_log, channel:, recipient:)
    return unless delivery_log.persisted?
    return if delivery_log.channel.blank? && delivery_log.recipient.blank?
    return if delivery_log.channel == channel && delivery_log.recipient == recipient

    raise ArgumentError, "Idempotency key already used with different channel or recipient"
  end

  def lifecycle_service_for(delivery_log)
    Documents::LifecycleService.new(
      actor: delivery_log.doctor,
      request_id: delivery_log.request_id,
      request_origin: "background_job:document_channel_delivery",
      user_agent: "sidekiq/document_channel_delivery_job"
    )
  end
end
