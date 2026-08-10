require "securerandom"

module Deliveries
  module Adapters
    class EmailAdapter < BaseAdapter
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

      def provider_name
        Rails.application.config.x.sendgrid.enabled ? "sendgrid" : "action_mailer"
      end
    end
  end
end
