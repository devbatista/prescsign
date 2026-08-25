module Deliveries
  module Adapters
    class BaseAdapter
      # Um canal só é oferecido ao usuário quando o adapter tem provedor por
      # trás. O default é falso de propósito: adapter novo nasce indisponível
      # até declarar o contrário, e não por esquecimento vira promessa de envio.
      def self.available?
        false
      end

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
