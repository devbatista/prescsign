module Deliveries
  class AdapterFactory
    CHANNEL_ADAPTERS = {
      "email" => Adapters::EmailAdapter,
      "sms" => Adapters::SmsAdapter,
      "whatsapp" => Adapters::WhatsappAdapter
    }.freeze

    def self.build(channel:, document:, recipient:, metadata: {})
      normalized_channel = channel.to_s.strip.downcase

      adapter_class = CHANNEL_ADAPTERS[normalized_channel]
      raise ArgumentError, "Unsupported channel: #{channel}" if adapter_class.nil?

      adapter_class.new(document:, recipient:, metadata:)
    end
  end
end
