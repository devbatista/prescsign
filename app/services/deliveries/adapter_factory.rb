module Deliveries
  class AdapterFactory
    CHANNEL_ADAPTERS = {
      "email" => Adapters::EmailAdapter,
      "sms" => Adapters::SmsAdapter,
      "whatsapp" => Adapters::WhatsappAdapter
    }.freeze

    # Canais com provedor real por trás. SMS e WhatsApp seguem mapeados acima
    # (DeliveryLogs antigos guardam esses valores e os adapters precisam existir
    # para falhar de forma tipada), mas não entregam nada. Quem promete envio ao
    # usuário — controller, serviço — consulta esta lista antes de enfileirar.
    AVAILABLE_CHANNELS = %w[email].freeze

    def self.available?(channel)
      AVAILABLE_CHANNELS.include?(channel.to_s.strip.downcase)
    end

    def self.build(channel:, document:, recipient:, metadata: {})
      normalized_channel = channel.to_s.strip.downcase

      adapter_class = CHANNEL_ADAPTERS[normalized_channel]
      raise ArgumentError, "Unsupported channel: #{channel}" if adapter_class.nil?

      adapter_class.new(document:, recipient:, metadata:)
    end
  end
end
