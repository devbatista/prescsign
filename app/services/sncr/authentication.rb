require "uri"

module Sncr
  # Orquestra a autenticação Gov.br (OAuth2/OIDC) exigida pela API do SNCR:
  # monta a URL de início do fluxo e troca o session_id (recebido no callback)
  # pelo access_token. O login efetivo acontece no Gov.br via Keycloak da Anvisa.
  #
  # Fluxo: /auth/login (redirect ao Gov.br) -> callback com ?session_id ->
  # /auth/token (access_token). Ver docs/sncr/SNCR_INTEGRATION.md.
  class Authentication
    BR_SUFFIX = ".br".freeze

    def initialize(
      base_url: Rails.application.config.x.sncr.base_url,
      client_url: Rails.application.config.x.sncr.auth_callback_url,
      client: nil
    )
      @base_url = base_url.to_s.chomp("/")
      @client_url = client_url.to_s
      @client = client
    end

    # URL de início do fluxo OIDC no SNCR. O SNCR redireciona ao Gov.br e, ao
    # final, devolve o navegador para o client_url (nosso callback) com session_id.
    def login_url(state: nil)
      raise Sncr::Error, "URL base do SNCR não configurada" if @base_url.blank?
      raise Sncr::Error, "client_url (callback) do SNCR não configurada" if @client_url.blank?

      query = { client_url: client_origin }
      query[:state] = state if state.present?
      "#{@base_url}/auth/login?#{URI.encode_www_form(query)}"
    end

    # Troca o session_id (recebido no callback) pelo access_token de curta duração.
    def exchange_session!(session_id:)
      client.exchange_token(session_id: session_id)
    end

    private

    # A Anvisa valida o client_url de forma ingênua: pega o último segmento
    # depois da última "/" e exige que termine em `.br`. Um path qualquer
    # (".../sncr/auth/callback" -> "callback") ou uma porta explícita
    # ("app.exemplo.com.br:8080") derrubam o fluxo com 403 "Domínio não
    # autorizado" antes mesmo de chegar ao Gov.br.
    #
    # Por isso enviamos só a ORIGEM: o path configurado é descartado aqui, e o
    # retorno é capturado na raiz do subdomínio `app.` pela rota condicional de
    # `config/routes/app.rb`. Ver docs/sncr/SNCR_INTEGRATION.md, seção 4.2.1.
    def client_origin
      uri = URI.parse(@client_url)
      raise Sncr::Error, "client_url do SNCR inválido: #{@client_url}" if uri.host.blank?

      origin = "#{uri.scheme}://#{uri.host}"
      unless origin.end_with?(BR_SUFFIX)
        raise Sncr::Error,
              "A Anvisa só aceita client_url de domínio #{BR_SUFFIX} (recebido: #{origin}). " \
              "Ajuste SNCR_AUTH_CALLBACK_URL para a origem pública do app, sem path nem porta."
      end

      origin
    rescue URI::InvalidURIError
      raise Sncr::Error, "client_url do SNCR inválido: #{@client_url}"
    end

    def client
      @client ||= Sncr::ClientFactory.build(base_url: @base_url)
    end
  end
end
