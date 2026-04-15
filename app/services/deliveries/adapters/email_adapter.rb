require "securerandom"

module Deliveries
  module Adapters
    class EmailAdapter < BaseAdapter
      def call
        message = DocumentDeliveryMailer.with(
          document: document,
          recipient: recipient,
          metadata: metadata
        ).notify_document.deliver_now

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
