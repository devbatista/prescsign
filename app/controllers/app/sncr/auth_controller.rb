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
      include SncrErrorReporting

      def start
        return connect_fake! if ::Sncr::ClientFactory.fake?

        redirect_to authentication.login_url(state: safe_return_to),
                    allow_other_host: true
      rescue ::Sncr::Error => e
        # Aqui só falha por configuração nossa (base_url ou client_url inválidos):
        # ninguém conecta até alguém do time corrigir, então alerta.
        redirect_to app_root_path,
                    alert: report_sncr_error(
                      e,
                      category: "sncr_auth_config",
                      alert: "Não foi possível conectar ao SNCR agora. " \
                             "Tente novamente em instantes; se o erro persistir, nosso time já foi avisado."
                    )
      end

      def callback
        token = authentication.exchange_session!(session_id: params[:session_id])
        # O access_token é um JWT grande — vai no Redis (server-side), não no
        # cookie de sessão, que estoura o limite de 4KB. Ver Sncr::TokenStore.
        token_store.write(token.access_token)
        redirect_to safe_return_to || app_root_path, notice: "Autenticado no SNCR."
      rescue ::Sncr::Error => e
        # session_id é de uso único e expira em ~30s: recarregar a página ou voltar
        # no histórico já cai aqui. Condição cotidiana do usuário — loga, não alerta.
        redirect_to app_root_path,
                    alert: report_sncr_error(
                      e,
                      category: "sncr_auth_exchange",
                      alert: "Não foi possível concluir a conexão com o SNCR. Tente conectar novamente.",
                      notify: false
                    )
      end

      private

      # Modo simulado (SNCR_FAKE, nunca em produção): não há Gov.br para visitar,
      # então emitimos o token na hora e devolvemos o médico à tela de origem —
      # o mesmo TokenStore e o mesmo `state` do fluxo real, sem a ida à Anvisa.
      def connect_fake!
        token = authentication.exchange_session!(session_id: "fake-session")
        token_store.write(token.access_token)
        redirect_to safe_return_to || app_root_path,
                    notice: "Conectado ao SNCR em modo simulado — as numerações são de teste."
      end

      def authentication
        ::Sncr::Authentication.new
      end

      def token_store
        ::Sncr::TokenStore.new(user_id: current_user.id)
      end

      # Só aceita caminhos internos como retorno (evita open redirect via state).
      def safe_return_to
        value = params[:state].presence || params[:return_to].presence
        value if value.is_a?(String) && value.start_with?("/") && !value.start_with?("//")
      end
    end
  end
end
