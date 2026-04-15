require "timeout"

module Deliveries
  class ChannelDispatcher
    def initialize(document:, channel:, recipient:, metadata: {})
      @document = document
      @channel = channel.to_s
      @recipient = recipient.to_s
      @metadata = metadata.to_h
    end

    def call
      raw_response = with_timeout { adapter.call }
      Deliveries::ResponseValidator.validate!(raw_response)
    rescue Deliveries::DeliveryError
      raise
    rescue Timeout::Error => e
      raise Deliveries::TimeoutError.new("Delivery timeout for channel #{@channel}", original: e)
    rescue StandardError => e
      raise build_provider_error(e)
    end

    private

    def adapter
      @adapter ||= Deliveries::AdapterFactory.build(
        channel: @channel,
        document: @document,
        recipient: @recipient,
        metadata: @metadata
      )
    end

    def with_timeout(&block)
      Timeout.timeout(timeout_seconds, &block)
    end

    def timeout_seconds
      configured = Rails.application.config.x.deliveries.timeout_seconds.to_f
      configured.positive? ? configured : 10.0
    end

    def build_provider_error(error)
      return Deliveries::TransientProviderError.new("Transient provider failure for channel #{@channel}", original: error) if Deliveries::ErrorClassifier.transient?(error)

      Deliveries::PermanentProviderError.new("Permanent provider failure for channel #{@channel}", original: error)
    end
  end
end
