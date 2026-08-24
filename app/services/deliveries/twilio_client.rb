require "json"
require "net/http"
require "uri"

module Deliveries
  # Cliente da Programmable Messaging API do Twilio. Segue o padrão Net::HTTP
  # puro dos demais provedores externos (`Sncr::Client`,
  # `Signatures::EvalCryptoCuboProvider`): sem gem nova, sem dependência extra.
  #
  # Contrato (docs.twilio.com/messaging/api/message-resource):
  # POST /2010-04-01/Accounts/{AccountSid}/Messages.json, Basic Auth com
  # AccountSid/AuthToken e corpo form-encoded. Para WhatsApp, `To` e `From`
  # levam o prefixo de canal `whatsapp:` sobre o número em E.164.
  class TwilioClient
    Message = Data.define(:sid, :status, :error_code, :error_message)

    # Status com que a API responde quando a mensagem foi aceita para envio. O
    # desfecho real (`delivered`, `undelivered`, `read`) só chega por webhook de
    # status, que ainda não existe aqui — ver docs/SISTEMA_TECNICO_DETALHADO.md.
    ACCEPTED_STATUSES = %w[queued accepted scheduled sending sent delivered read].freeze

    # 429 é limite de taxa (o sandbox aceita uma mensagem a cada três segundos)
    # e merece nova tentativa; os demais 4xx são erro de requisição e não mudam
    # de resultado ao repetir.
    TRANSIENT_HTTP_CODES = %w[429].freeze

    def initialize(
      account_sid: Rails.application.config.x.twilio.account_sid,
      auth_token: Rails.application.config.x.twilio.auth_token,
      base_url: Rails.application.config.x.twilio.base_url,
      timeout_seconds: Rails.application.config.x.twilio.timeout_seconds
    )
      @account_sid = account_sid.to_s
      @auth_token = auth_token.to_s
      @base_url = base_url.to_s.chomp("/")
      @timeout_seconds = timeout_seconds.to_i.positive? ? timeout_seconds.to_i : 8
    end

    def send_message!(from:, to:, body:)
      if @account_sid.empty? || @auth_token.empty?
        raise Deliveries::PermanentProviderError, "Credenciais do Twilio ausentes"
      end

      response = post_message(from: from, to: to, body: body)
      parsed = parse_body(response)

      raise provider_error(response, parsed) unless response.is_a?(Net::HTTPSuccess)

      build_message(parsed)
    rescue JSON::ParserError => e
      raise Deliveries::UnexpectedProviderResponseError.new(
        "Resposta ilegível do Twilio: #{e.message}", original: e
      )
    end

    private

    # Erros de rede (timeout, conexão recusada, DNS) sobem crus de propósito: o
    # ChannelDispatcher já os classifica como transitórios via ErrorClassifier.
    def post_message(from:, to:, body:)
      uri = URI.parse("#{@base_url}/2010-04-01/Accounts/#{@account_sid}/Messages.json")

      request = Net::HTTP::Post.new(uri)
      request.basic_auth(@account_sid, @auth_token)
      request["Accept"] = "application/json"
      request.set_form_data("From" => from, "To" => to, "Body" => body)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout_seconds
      http.read_timeout = @timeout_seconds

      http.request(request)
    end

    def build_message(parsed)
      message = Message.new(
        sid: parsed["sid"].to_s,
        status: parsed["status"].to_s,
        error_code: parsed["error_code"],
        error_message: parsed["error_message"]
      )

      if message.sid.empty?
        raise Deliveries::UnexpectedProviderResponseError, "Twilio respondeu sem sid da mensagem"
      end

      # A API pode aceitar o POST e ainda assim devolver a mensagem já rejeitada
      # (`failed`/`undelivered`). Tratar isso como sucesso reintroduziria a
      # entrega fantasma que este canal acabou de deixar de produzir.
      unless ACCEPTED_STATUSES.include?(message.status)
        raise Deliveries::PermanentProviderError,
              "Twilio recusou a mensagem (status #{message.status}): " \
              "#{message.error_code} #{message.error_message}".strip
      end

      message
    end

    def provider_error(response, parsed)
      message = "Twilio retornou HTTP #{response.code}: " \
                "#{parsed['code']} #{parsed['message'] || response.message}".strip

      if TRANSIENT_HTTP_CODES.include?(response.code) || response.is_a?(Net::HTTPServerError)
        return Deliveries::TransientProviderError.new(message)
      end

      Deliveries::PermanentProviderError.new(message)
    end

    def parse_body(response)
      body = response.body.to_s
      return {} if body.strip.empty?

      JSON.parse(body)
    end
  end
end
