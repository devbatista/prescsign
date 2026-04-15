module Deliveries
  module Adapters
    class SmsAdapter < BaseAdapter
      def call
        build_fake_adapter.call
      end

      private

      def build_fake_adapter
        FakeAdapter.new(
          document: document,
          recipient: recipient,
          channel: "sms",
          provider_name: "twilio",
          metadata: metadata
        )
      end
    end
  end
end
