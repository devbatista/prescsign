class DocumentChannelDeliveryJob < NotificationJob
  RETRY_ATTEMPTS = 5
  RETRY_BACKOFF_BASE_SECONDS = 5
  RETRY_BACKOFF_MAX_SECONDS = 300

  discard_on ArgumentError
  discard_on ActiveRecord::RecordNotFound

  retry_on StandardError,
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

    return if already_processed?(delivery_log)

    mark_processing!(delivery_log, metadata)

    dispatch_result = Deliveries::ChannelDispatcher.new(
      document: document,
      channel: normalized_channel,
      recipient: normalized_recipient,
      metadata: metadata
    ).call

    mark_sent!(delivery_log, dispatch_result)
  rescue StandardError => e
    mark_failed!(delivery_log, e, metadata) if defined?(delivery_log) && delivery_log.present?
    raise
  end

  private

  def find_or_initialize_delivery_log(document:, channel:, recipient:, doctor_id:, patient_id:, request_id:, idempotency_key:, metadata:)
    log = if idempotency_key.present?
            DeliveryLog.where(idempotency_key: idempotency_key).first_or_initialize
          else
            DeliveryLog.new
          end

    log.document_id ||= document.id
    log.channel = channel
    log.recipient = recipient
    log.doctor_id ||= doctor_id || document.doctor_id
    log.patient_id ||= patient_id || document.patient_id
    log.request_id ||= request_id
    log.idempotency_key ||= idempotency_key
    log.metadata = log.metadata.merge(metadata.to_h)
    log
  end

  def already_processed?(delivery_log)
    delivery_log.persisted? && delivery_log.status.in?(%w[sent delivered])
  end

  def mark_processing!(delivery_log, metadata)
    next_attempt_number = delivery_log.persisted? ? delivery_log.attempt_number + 1 : 1
    delivery_log.update!(
      status: "processing",
      attempted_at: Time.current,
      attempt_number: next_attempt_number,
      error_code: nil,
      error_message: nil,
      metadata: delivery_log.metadata.merge(metadata.to_h)
    )
  end

  def mark_sent!(delivery_log, dispatch_result)
    status = dispatch_result.fetch(:status, "sent")
    delivered_at = status == "delivered" ? Time.current : nil

    delivery_log.update!(
      status: status,
      provider_name: dispatch_result[:provider_name],
      provider_message_id: dispatch_result[:provider_message_id],
      delivered_at: delivered_at,
      metadata: delivery_log.metadata.merge(dispatch_result.fetch(:metadata, {}))
    )
  end

  def mark_failed!(delivery_log, error, metadata)
    delivery_log.update!(
      status: "failed",
      error_code: error.class.name,
      error_message: error.message.to_s.truncate(2000),
      attempted_at: Time.current,
      metadata: delivery_log.metadata.merge(metadata.to_h)
    )
  rescue StandardError
    # Never mask the original delivery error.
    nil
  end
end
