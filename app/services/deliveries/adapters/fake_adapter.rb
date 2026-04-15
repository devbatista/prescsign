require "securerandom"

module Deliveries
  module Adapters
    class FakeAdapter < BaseAdapter
      def initialize(document:, recipient:, channel:, provider_name:, metadata: {})
        super(document:, recipient:, metadata:)
        @channel = channel.to_s
        @provider_name = provider_name.to_s
      end

      def call
        {
          status: "sent",
          provider_name: @provider_name,
          provider_message_id: SecureRandom.uuid,
          metadata: {
            channel: @channel,
            mode: "fake",
            simulated: true
          }.merge(metadata)
        }
      end
    end
  end
end
