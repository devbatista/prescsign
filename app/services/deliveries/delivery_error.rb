module Deliveries
  class DeliveryError < StandardError
    attr_reader :original

    def initialize(message = "Delivery integration error", original: nil)
      super(message)
      @original = original
    end
  end
end
