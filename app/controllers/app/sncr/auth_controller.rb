module App
  module Sncr
    # Fluxo de autenticação Gov.br (OIDC) do médico junto ao SNCR, dentro do
    # painel (app.). `start` redireciona ao SNCR/Gov.br; `callback` recebe o
    # session_id de volta e o troca pelo access_token, guardado na sessão para
    # uso nas requisições de numeração.
    #
    # Observação: usa `::Sncr::` (top-level) para não colidir com este módulo
    # App::Sncr.
    class AuthController < ApplicationController
      def start
        redirect_to authentication.login_url(state: safe_return_to),
                    allow_other_host: true
      rescue ::Sncr::Error => e
        redirect_to app_root_path,
                    alert: "Não foi possível iniciar a autenticação no SNCR: #{e.message}"
      end

      def callback
        token = authentication.exchange_session!(session_id: params[:session_id])
        session[:sncr] = {
          "access_token" => token.access_token,
          "obtained_at" => Time.current.iso8601
        }
        redirect_to safe_return_to || app_root_path, notice: "Autenticado no SNCR."
      rescue ::Sncr::Error => e
        redirect_to app_root_path, alert: "Falha na autenticação no SNCR: #{e.message}"
      end

      private

      def authentication
        ::Sncr::Authentication.new
      end

      # Só aceita caminhos internos como retorno (evita open redirect via state).
      def safe_return_to
        value = params[:state].presence || params[:return_to].presence
        value if value.is_a?(String) && value.start_with?("/") && !value.start_with?("//")
      end
    end
  end
end
