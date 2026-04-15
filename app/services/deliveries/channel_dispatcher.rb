module Deliveries
  class ChannelDispatcher
    def initialize(document:, channel:, recipient:, metadata: {})
      @document = document
      @channel = channel.to_s
      @recipient = recipient.to_s
      @metadata = metadata.to_h
    end

    def call
      adapter.call
    end

    private

    def adapter
      @adapter ||= Deliveries::AdapterFactory.build(
        channel: @channel,
        document: @document,
        recipient: @recipient,
        metadata: @metadata
      )
    end
  end
end
