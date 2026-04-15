module Deliveries
  module Adapters
    class BaseAdapter
      def initialize(document:, recipient:, metadata: {})
        @document = document
        @recipient = recipient.to_s
        @metadata = metadata.to_h
      end

      def call
        raise NotImplementedError, "#{self.class.name} must implement #call"
      end

      private

      attr_reader :document, :recipient, :metadata
    end
  end
end
