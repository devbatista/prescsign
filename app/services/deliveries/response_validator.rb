module Deliveries
  class ResponseValidator
    SUPPORTED_STATUSES = %w[sent delivered failed].freeze

    def self.validate!(response)
      raise UnexpectedProviderResponseError, "Provider response must be a Hash" unless response.is_a?(Hash)

      status = fetch_value(response, :status)
      provider_name = fetch_value(response, :provider_name)
      provider_message_id = fetch_value(response, :provider_message_id)
      metadata = fetch_value(response, :metadata, default: {})

      unless SUPPORTED_STATUSES.include?(status.to_s)
        raise UnexpectedProviderResponseError, "Unsupported provider status: #{status.inspect}"
      end

      if provider_name.to_s.strip.empty? || provider_message_id.to_s.strip.empty?
        raise UnexpectedProviderResponseError, "Provider response must include provider_name and provider_message_id"
      end
      raise UnexpectedProviderResponseError, "Provider metadata must be a Hash" unless metadata.is_a?(Hash)

      {
        status: status.to_s,
        provider_name: provider_name.to_s,
        provider_message_id: provider_message_id.to_s,
        metadata: metadata
      }
    end

    def self.fetch_value(response, key, default: nil)
      response[key] || response[key.to_s] || default
    end
    private_class_method :fetch_value
  end
end
