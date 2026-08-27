# Trata falhas da integração com o SNCR (Anvisa) sem vazar o texto técnico para
# a tela. As mensagens de Sncr::Error descrevem a nossa configuração ou a resposta
# crua da Anvisa ("A Anvisa só aceita client_url de domínio .br", "SNCR retornou
# HTTP 404: ...") — diagnóstico para o time, não orientação para o médico.
#
# O detalhe vai para o log estruturado e, quando alguém do time precisa agir,
# para o Sentry via Observability::CriticalAlertService. A tela recebe só uma
# mensagem genérica, no mesmo espírito das falhas de assinatura tratadas em
# App::DocumentsController#sign.
module SncrErrorReporting
  extend ActiveSupport::Concern

  SNCR_GENERIC_ALERT = "Não foi possível concluir a operação com o SNCR agora. " \
                       "Tente novamente em instantes; se o erro persistir, nosso time já foi avisado.".freeze

  private

  # Registra a falha e devolve a mensagem que pode ir para a tela.
  #
  # `notify: false` para condições do dia a dia do usuário (sessão do Gov.br
  # expirada, por exemplo), que só poluiriam o alerta crítico — mesma escolha
  # feita para PIN incorreto em Documents::SigningService.
  def report_sncr_error(error, category:, alert: SNCR_GENERIC_ALERT, notify: true, **context)
    payload = {
      user_id: current_user&.id,
      request_id: request.request_id,
      ip_address: request.remote_ip
    }.merge(context)

    if notify
      Observability::CriticalAlertService.notify!(category: category, exception: error, context: payload)
    else
      Rails.logger.error(
        payload.merge(
          event: "sncr_error",
          category: category,
          error_class: error.class.name,
          error_message: error.message.to_s
        )
      )
    end

    alert
  end
end
