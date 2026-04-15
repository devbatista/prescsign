require "securerandom"

module Deliveries
  class ChannelDispatcher
    def initialize(document:, channel:, recipient:, metadata: {})
      @document = document
      @channel = channel.to_s
      @recipient = recipient.to_s
      @metadata = metadata.to_h
    end

    def call
      case @channel
      when "email" then dispatch_email
      when "sms" then dispatch_sms
      when "whatsapp" then dispatch_whatsapp
      else
        raise ArgumentError, "Unsupported channel: #{@channel}"
      end
    end

    private

    def dispatch_email
      message = DocumentDeliveryMailer.with(
        document: @document,
        recipient: @recipient,
        metadata: @metadata
      ).notify_document.deliver_now

      {
        status: "sent",
        provider_name: email_provider_name,
        provider_message_id: message.message_id.presence || SecureRandom.uuid,
        metadata: { channel: "email" }
      }
    end

    def dispatch_sms
      {
        status: "sent",
        provider_name: "twilio",
        provider_message_id: SecureRandom.uuid,
        metadata: { channel: "sms", mode: "stub" }
      }
    end

    def dispatch_whatsapp
      {
        status: "sent",
        provider_name: "whatsapp_cloud_api",
        provider_message_id: SecureRandom.uuid,
        metadata: { channel: "whatsapp", mode: "stub" }
      }
    end

    def email_provider_name
      Rails.application.config.x.sendgrid.enabled ? "sendgrid" : "action_mailer"
    end
  end
end
