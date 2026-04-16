sentry_config = Rails.application.config.x.sentry

if sentry_config.enabled
  Sentry.init do |config|
    config.dsn = sentry_config.dsn
    config.environment = sentry_config.environment
    config.traces_sample_rate = sentry_config.traces_sample_rate
    config.breadcrumbs_logger = [:active_support_logger, :http_logger]
  end
end
