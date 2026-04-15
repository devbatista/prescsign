require "net/protocol"

module Deliveries
  module ErrorClassifier
    module_function

    TRANSIENT_ERROR_CLASSES = [
      Timeout::Error,
      Net::OpenTimeout,
      Net::ReadTimeout,
      Errno::ETIMEDOUT,
      Errno::ECONNRESET,
      Errno::ECONNREFUSED,
      EOFError,
      SocketError
    ].freeze

    def transient?(error)
      TRANSIENT_ERROR_CLASSES.any? { |klass| error.is_a?(klass) }
    end
  end
end
