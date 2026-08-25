module Deliveries
  class AdapterFactory
    CHANNEL_ADAPTERS = {
      "email" => Adapters::EmailAdapter,
      "sms" => Adapters::SmsAdapter,
      "whatsapp" => Adapters::WhatsappAdapter
    }.freeze

    # Canal disponível é canal com provedor por trás, e quem sabe disso é o
    # próprio adapter — o do WhatsApp depende de credencial do Twilio, que muda
    # por ambiente. Quem promete envio ao usuário (interface, controller)
    # pergunta aqui antes de enfileirar; `DeliveryLog::CHANNELS` continua
    # aceitando todos os valores porque registros históricos usam todos eles.
    def self.available?(channel)
      adapter_class = CHANNEL_ADAPTERS[normalize(channel)]
      adapter_class.present? && adapter_class.available?
    end

    def self.available_channels
      CHANNEL_ADAPTERS.select { |_channel, adapter_class| adapter_class.available? }.keys
    end

    def self.normalize(channel)
      channel.to_s.strip.downcase
    end
    private_class_method :normalize

    def self.build(channel:, document:, recipient:, metadata: {})
      normalized_channel = normalize(channel)

      adapter_class = CHANNEL_ADAPTERS[normalized_channel]
      raise ArgumentError, "Unsupported channel: #{channel}" if adapter_class.nil?

      adapter_class.new(document:, recipient:, metadata:)
    end
  end
end
