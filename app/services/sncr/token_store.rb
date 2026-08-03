require "base64"
require "json"

module Sncr
  # Guarda o access_token do SNCR (JWT de ~3-4KB) fora do cookie de sessão. O
  # cookie store do Rails tem limite de 4KB; colocar o JWT em `session[:sncr]`
  # estoura (ActionDispatch::Cookies::CookieOverflow). Usa o Redis já disponível
  # (mesma infra do Rack::Attack), keyado pelo usuário, com TTL derivado do
  # claim `exp` do próprio JWT — com fallback conservador quando não dá pra ler.
  class TokenStore
    KEY_PREFIX = "sncr:token:".freeze
    FALLBACK_TTL = 15.minutes
    MAX_TTL = 1.hour

    def initialize(user_id:, redis: nil)
      raise ArgumentError, "user_id é obrigatório" if user_id.blank?

      @key = "#{KEY_PREFIX}#{user_id}"
      @redis = redis || Redis.new(url: Rails.application.config.x.redis_url)
    end

    def write(access_token)
      @redis.set(@key, access_token, ex: ttl_for(access_token))
      access_token
    end

    def read
      @redis.get(@key)
    end

    def clear
      @redis.del(@key)
    end

    private

    # TTL = tempo restante do JWT (claim `exp`), limitado a [1s, MAX_TTL]. Sem
    # `exp` legível, cai no fallback — assim um token expirado no SNCR não fica
    # indefinidamente no Redis (a chamada seguinte à API devolve 401 de qualquer
    # forma, e o médico reconecta).
    def ttl_for(access_token)
      exp = jwt_exp(access_token)
      return FALLBACK_TTL.to_i if exp.nil?

      (exp - Time.current.to_i).clamp(1, MAX_TTL.to_i)
    end

    def jwt_exp(access_token)
      payload = access_token.to_s.split(".")[1]
      return if payload.blank?

      json = Base64.urlsafe_decode64(payload + ("=" * ((4 - payload.length % 4) % 4)))
      JSON.parse(json)["exp"]&.to_i
    rescue ArgumentError, JSON::ParserError
      nil
    end
  end
end
