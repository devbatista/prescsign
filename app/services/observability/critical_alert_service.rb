module Observability
  class CriticalAlertService
    EXCEPTION_ALERT_MARKER = :@prescsign_critical_alert_sent

    class << self
      def notify!(category:, exception:, context: {})
        return false if already_alerted?(exception)

        mark_as_alerted!(exception)
        log_alert(category: category, exception: exception, context: context)
        sentry_alert(category: category, exception: exception, context: context)
        true
      end

      private

      def already_alerted?(exception)
        exception.instance_variable_defined?(EXCEPTION_ALERT_MARKER)
      end

      def mark_as_alerted!(exception)
        exception.instance_variable_set(EXCEPTION_ALERT_MARKER, true)
      end

      def log_alert(category:, exception:, context:)
        Rails.logger.error(
          {
            event: "critical_alert",
            category: category,
            error_class: exception.class.name,
            error_message: exception.message.to_s,
            context: context,
            backtrace: exception.backtrace&.first(20)
          }
        )
      end

      def sentry_alert(category:, exception:, context:)
        return unless defined?(Sentry)

        Sentry.with_scope do |scope|
          scope.set_tags(alert_category: category)
          scope.set_extras(context)
          Sentry.capture_exception(exception)
        end
      rescue StandardError
        nil
      end
    end
  end
end
