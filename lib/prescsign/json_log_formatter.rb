require "json"
require "logger"

module Prescsign
  class JsonLogFormatter < ::Logger::Formatter
    FILTERED = "[FILTERED]".freeze
    SENSITIVE_KEY_PATTERN = /
      passw|secret|token|_key|crypt|salt|certificate|otp|ssn|cpf|cnpj|
      authorization|cookie|set-cookie|api_key|email|phone
    /ix

    def call(severity, time, progname, msg)
      payload = {
        timestamp: time.utc.iso8601(3),
        severity: severity,
        progname: progname,
        pid: Process.pid
      }.compact

      case msg
      when Hash
        payload.merge!(sanitize_hash(msg))
      when Exception
        payload[:message] = msg.message
        payload[:error_class] = msg.class.name
        payload[:backtrace] = msg.backtrace&.first(10)
      else
        payload[:message] = msg2str(msg)
      end

      "#{payload.to_json}\n"
    end

    private

    def sanitize_hash(hash)
      hash.to_h.each_with_object({}) do |(key, value), sanitized|
        key_str = key.to_s
        sanitized[key] =
          if sensitive_key?(key_str)
            FILTERED
          else
            sanitize_value(value)
          end
      end
    end

    def sanitize_array(array)
      Array(array).map { |item| sanitize_value(item) }
    end

    def sanitize_value(value)
      case value
      when Hash
        sanitize_hash(value)
      when Array
        sanitize_array(value)
      else
        value
      end
    end

    def sensitive_key?(key)
      key.match?(SENSITIVE_KEY_PATTERN)
    end
  end
end
