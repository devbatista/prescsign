module Deliveries
  module Adapters
    class WhatsappAdapter < BaseAdapter
      def call
        build_fake_adapter.call
      end

      private

      def build_fake_adapter
        FakeAdapter.new(
          document: document,
          recipient: recipient,
          channel: "whatsapp",
          provider_name: "whatsapp_cloud_api",
          metadata: metadata
        )
      end
    end
  end
end
