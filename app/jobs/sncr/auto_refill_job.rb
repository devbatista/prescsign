module Sncr
  # Executa o reabastecimento oportunista decidido por Sncr::AutoRefill.
  #
  # Recebe **ids**, nunca o token: o payload do Sidekiq é legível no Redis e no
  # Sidekiq Web, e o access_token autoriza pedir numeração em nome do médico na
  # Anvisa. O token é lido do TokenStore aqui dentro — se expirou entre o
  # enfileiramento e a execução, o job simplesmente não faz nada.
  #
  # **Sem retry, de propósito.** O retry padrão transformaria uma indisponibilidade
  # da Anvisa em enxurrada de chamadas, e cada tentativa sem resposta conta
  # contra a cota mensal de RCE/RET. Quem perdeu a janela tenta no próximo
  # gatilho.
  class AutoRefillJob < ApplicationJob
    queue_as :default

    discard_on ActiveJob::DeserializationError

    def perform(user_id:, doctor_profile_id:, sncr_type:)
      doctor_profile = DoctorProfile.find_by(id: doctor_profile_id)
      return skip!("prescritor não encontrado", user_id, sncr_type) if doctor_profile.nil?

      token = TokenStore.new(user_id: user_id).read
      return skip!("sem token do Gov.br", user_id, sncr_type) if token.blank?

      # Reavalia a elegibilidade agora: entre o enfileiramento e aqui, outro job
      # pode já ter reposto o saldo ou gasto a cota.
      unless AutoRefill.eligible_types(doctor_profile: doctor_profile, only: sncr_type).include?(sncr_type)
        return skip!("não mais elegível", user_id, sncr_type)
      end

      NumberingBatch.request!(
        doctor_profile: doctor_profile,
        sncr_type: sncr_type,
        origin: "auto_refill",
        user: User.find_by(id: user_id),
        access_token: token
      )
    rescue Sncr::Error => e
      # Cota estourada e recusa da Anvisa são desfechos esperados do
      # reabastecimento, não incidentes: o registro fica em
      # sncr_numbering_requests e o médico segue podendo pedir na mão.
      Rails.logger.info(
        event: "sncr_auto_refill_skipped",
        reason: e.class.name,
        error_message: e.message.to_s,
        user_id: user_id,
        sncr_type: sncr_type
      )
    rescue StandardError => e
      Observability::CriticalAlertService.notify!(
        category: "sncr_auto_refill_failure",
        exception: e,
        context: { job: self.class.name, user_id: user_id, sncr_type: sncr_type }
      )
    end

    private

    def skip!(reason, user_id, sncr_type)
      Rails.logger.info(
        event: "sncr_auto_refill_skipped", reason: reason, user_id: user_id, sncr_type: sncr_type
      )
      nil
    end
  end
end
