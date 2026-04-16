require "json"
require "logger"

module Prescsign
  class JsonLogFormatter < ::Logger::Formatter
    def call(severity, time, progname, msg)
      payload = {
        timestamp: time.utc.iso8601(3),
        severity: severity,
        progname: progname,
        pid: Process.pid
      }.compact

      case msg
      when Hash
        payload.merge!(msg)
      when Exception
        payload[:message] = msg.message
        payload[:error_class] = msg.class.name
        payload[:backtrace] = msg.backtrace&.first(10)
      else
        payload[:message] = msg2str(msg)
      end

      "#{payload.to_json}\n"
    end
  end
end
