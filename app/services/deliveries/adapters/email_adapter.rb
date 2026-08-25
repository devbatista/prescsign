require "securerandom"

module Deliveries
  module Adapters
    class EmailAdapter < BaseAdapter
      # Sempre disponível: em produção o relay é SMTP e nos demais ambientes o
      # próprio ActionMailer entrega (letter_opener em development, :test na suíte).
      def self.available?
        true
      end

      def call
        delivery = DocumentDeliveryMailer.with(
          document: document,
          recipient: recipient,
          metadata: metadata
        ).notify_document

        # A entrega precisa falhar alto: é o retorno do deliver_now que marca o
        # DeliveryLog como "sent". Com raise_delivery_errors desligado o mail
        # engole o erro de SMTP e um envio que nunca saiu vira "entregue" — sem
        # log, sem retry e sem alerta. Não dá para depender de ENV aqui: quem
        # decide o status da entrega é este adapter.
        delivery.message.raise_delivery_errors = true
        message = delivery.deliver_now

        {
          status: "sent",
          provider_name: provider_name,
          provider_message_id: message.message_id.presence || SecureRandom.uuid,
          metadata: { channel: "email" }.merge(metadata)
        }
      end

      private

      # O nome registrado no DeliveryLog precisa refletir por onde a mensagem
      # saiu de fato, não uma credencial presente no ambiente: em produção o
      # relay é SMTP (AWS SES), e nos demais ambientes o próprio ActionMailer
      # (letter_opener em development, :test na suíte).
      def provider_name
        ActionMailer::Base.delivery_method == :smtp ? "smtp" : "action_mailer"
      end
    end
  end
end
