require "uri"

module Sncr
  # Orquestra a autenticação Gov.br (OAuth2/OIDC) exigida pela API do SNCR:
  # monta a URL de início do fluxo e troca o session_id (recebido no callback)
  # pelo access_token. O login efetivo acontece no Gov.br via Keycloak da Anvisa.
  #
  # Fluxo: /auth/login (redirect ao Gov.br) -> callback com ?session_id ->
  # /auth/token (access_token). Ver docs/sncr/SNCR_INTEGRATION.md.
  class Authentication
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

      query = { client_url: @client_url }
      query[:state] = state if state.present?
      "#{@base_url}/auth/login?#{URI.encode_www_form(query)}"
    end

    # Troca o session_id (recebido no callback) pelo access_token de curta duração.
    def exchange_session!(session_id:)
      client.exchange_token(session_id: session_id)
    end

    private

    def client
      @client ||= Sncr::ClientFactory.build(base_url: @base_url)
    end
  end
end
