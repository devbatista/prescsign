require "json"
require "net/http"
require "uri"

module Sncr
  # Cliente HTTP da API do SNCR (Anvisa). Cobre a troca de token (após o login
  # Gov.br/OIDC) e os dois endpoints de requisição de numeração. Segue o padrão
  # Net::HTTP puro dos providers de assinatura (Signatures::IcpBrasilProvider).
  #
  # Contrato conforme o Manual da API SNCR — 1ª ed. (jun/2026). Ver
  # docs/sncr/SNCR_INTEGRATION.md.
  class Client
    Token = Data.define(:access_token, :token_type)
    Notificacao = Data.define(:numbers, :balance, :message)
    EspecialRetencao = Data.define(:range_start, :range_end, :quantity, :message)

    def initialize(
      base_url: Rails.application.config.x.sncr.base_url,
      timeout_seconds: Rails.application.config.x.sncr.timeout_seconds,
      access_token: nil
    )
      @base_url = base_url.to_s.chomp("/")
      @timeout_seconds = timeout_seconds.to_i.positive? ? timeout_seconds.to_i : 30
      @access_token = access_token
    end

    # Troca o session_id de uso único (recebido no callback) pelo access_token JWT.
    # GET /auth/token. Como o session_id é passado ainda depende de confirmação
    # no Swagger de homologação (aqui vai como query param).
    def exchange_token(session_id:)
      raise Sncr::Error, "session_id é obrigatório" if session_id.blank?

      response = get_json(path: "/auth/token", query: { session_id: session_id })
      Token.new(
        access_token: response.fetch("access_token"),
        token_type: response["token_type"].presence || "Bearer"
      )
    rescue KeyError => e
      raise Sncr::Error, "Resposta inválida do SNCR: #{e.message}"
    end

    # POST /numeracoes/notificacao-receita — tipos NRA/NRB/NRB2/NRR/NRT.
    # Retorna uma lista de números (até 50).
    def request_notificacao!(receita:, conselho:, uf:, documento:, quantidade:)
      response = post_json(
        path: "/numeracoes/notificacao-receita",
        body: { receita: receita, conselho: conselho, uf: uf, documento: documento, quantidade: quantidade }
      )
      Notificacao.new(
        numbers: Array(response["numeracoesReceita"] || response["numeroReceita"]),
        balance: response["saldoReceitas"],
        message: response["mensagem"]
      )
    end

    # POST /numeracoes/receita-especial-retencao — tipos RCE/RET.
    # Retorna um bloco contínuo de 1.000 números (inicio..fim).
    def request_especial_retencao!(conselho:, tipo:, documento:, uf:, cnpj:)
      response = post_json(
        path: "/numeracoes/receita-especial-retencao",
        body: { conselho: conselho, tipo: tipo, documento: documento, uf: uf, cnpj: cnpj }
      )
      EspecialRetencao.new(
        range_start: response["inicio"],
        range_end: response["fim"],
        quantity: response["quantidade"],
        message: response["mensagem"]
      )
    end

    private

    def get_json(path:, query: {})
      uri = build_uri(path, query)
      execute(Net::HTTP::Get.new(uri), uri)
    end

    def post_json(path:, body:)
      uri = build_uri(path)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)
      execute(request, uri)
    end

    def execute(request, uri)
      request["Accept"] = "application/json"
      request["Authorization"] = "Bearer #{@access_token}" if @access_token.present?

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout_seconds
      http.read_timeout = @timeout_seconds

      response = http.request(request)
      parsed = parse_body(response)
      return parsed if response.is_a?(Net::HTTPSuccess)

      raise Sncr::Error, error_message(response, parsed)
    rescue JSON::ParserError => e
      raise Sncr::Error, "Resposta inválida do SNCR: #{e.message}"
    rescue Timeout::Error, Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
      raise Sncr::Error, "SNCR indisponível: #{e.class}"
    end

    def build_uri(path, query = {})
      raise Sncr::Error, "URL base do SNCR não configurada" if @base_url.blank?

      uri = URI.join("#{@base_url}/", path.delete_prefix("/"))
      uri.query = URI.encode_www_form(query) if query.present?
      uri
    end

    def parse_body(response)
      body = response.body.to_s
      return {} if body.blank?

      JSON.parse(body)
    end

    def error_message(response, body)
      code = body["error_code"] || body["errorCode"] || response.code
      message = body["error_message"] || body["errorMessage"] || body["error"] || response.message
      "SNCR retornou HTTP #{response.code}: #{code} #{message}".strip
    end
  end
end
