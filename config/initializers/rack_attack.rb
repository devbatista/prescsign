# Throttling for the public authentication screens (brute-force / abuse guard).
# The old JSON API had its own header-based limiter; the session web layer needs
# its own. Counters are shared across processes via Redis (memory store in test).
class Rack::Attack
  # Shared, process-independent counter store. MemoryStore in test keeps the suite
  # hermetic (reset between examples in rails_helper). In dev/prod we use a raw Redis
  # client: rack-attack's RedisProxy only wraps a bare Redis, and redis-rb 5.x
  # serializes commands via an internal monitor (thread-safe), while all Puma
  # workers/pods share the same Redis keys. (We avoid ActiveSupport::Cache::
  # RedisCacheStore: Rails 7.1 builds its pool with a positional ConnectionPool.new
  # call that connection_pool 3.x — pulled in by sidekiq 8 — rejects.)
  self.cache.store =
    if Rails.env.test?
      ActiveSupport::Cache::MemoryStore.new
    else
      Redis.new(url: Rails.application.config.x.redis_url)
    end

  # Auth POST/PUT endpoints (same path across subdomains).
  LOGIN_PATH        = "/sign-in".freeze
  REGISTER_PATH     = "/sign-up".freeze
  FORGOT_PATH       = "/forgot-password".freeze
  RESET_PATH        = "/reset-password".freeze
  RESEND_PATH       = "/resend-confirmation".freeze

  # Login: by IP and by email (blunts both spraying and single-account targeting).
  throttle("auth/login/ip", limit: 10, period: 60) do |req|
    req.ip if req.post? && req.path == LOGIN_PATH
  end

  throttle("auth/login/email", limit: 10, period: 600) do |req|
    if req.post? && req.path == LOGIN_PATH
      req.params.dig("user", "email").to_s.strip.downcase.presence
    end
  end

  # Registration by IP.
  throttle("auth/register/ip", limit: 10, period: 600) do |req|
    req.ip if req.post? && req.path == REGISTER_PATH
  end

  # Password recovery (request + reset) by IP.
  throttle("auth/password/ip", limit: 5, period: 600) do |req|
    req.ip if (req.post? && req.path == FORGOT_PATH) || (req.put? && req.path == RESET_PATH)
  end

  # Resend confirmation by IP.
  throttle("auth/confirmation/ip", limit: 5, period: 600) do |req|
    req.ip if req.post? && req.path == RESEND_PATH
  end

  # Friendly 429 with Retry-After.
  self.throttled_responder = lambda do |req|
    period = req.env.dig("rack.attack.match_data", :period)
    headers = { "Content-Type" => "text/plain; charset=utf-8" }
    headers["Retry-After"] = period.to_s if period
    [429, headers, ["Muitas tentativas. Aguarde alguns instantes e tente novamente.\n"]]
  end
end
