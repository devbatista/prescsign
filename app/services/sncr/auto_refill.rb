module Sncr
  # Política do reabastecimento oportunista do pool (§6.1 de
  # docs/sncr/SNCR_INTEGRATION.md). Decide *se* vale pedir; quem pede é o
  # AutoRefillJob, e quem aplica a cota é o NumberingBatch.
  #
  # **Oportunista, não agendado.** O access_token do Gov.br é artefato de sessão
  # (Redis, TTL ≤ 1h, obtido por OIDC interativo), então um job periódico
  # acordaria sem token na maior parte das execuções. O gatilho é evento: depois
  # da assinatura e na visita ao painel, enquanto o médico está por perto. Sem
  # token, nada acontece de fundo e a tela assume a conversa.
  #
  # Não faz I/O externo: só lê o banco e a configuração.
  class AutoRefill
    # "Já utilizado antes" com prazo. Um tipo consumido uma vez há dois anos não
    # é prática corrente do prescritor e não justifica gastar cota — em RCE/RET,
    # gastaria uma das 3 solicitações do mês.
    USAGE_LOOKBACK = 180.days

    # Janela entre reabastecimentos automáticos do mesmo médico e tipo. É o que
    # impede a rajada: dez assinaturas seguidas enfileiram dez jobs, e do
    # segundo em diante todos caem aqui ou já encontram o saldo reposto.
    COOLDOWN = 30.minutes

    class << self
      def enabled?
        Rails.application.config.x.sncr.auto_refill
      end

      # Tipos que merecem reabastecimento agora. `only` restringe a um tipo —
      # usado no gatilho pós-assinatura, que sabe exatamente qual foi consumido.
      def eligible_types(doctor_profile:, only: nil, now: Time.current)
        return [] unless enabled?

        candidates = only ? Array(only).map(&:to_s) : ::Prescription::SNCR_TYPES
        quota = NumberingQuota.for(doctor_profile, now: now)
        balance = ::SncrNumbering.balance_for(doctor_profile)

        candidates.select do |sncr_type|
          eligible?(doctor_profile: doctor_profile, sncr_type: sncr_type,
                    quota: quota, balance: balance, now: now)
        end
      end

      # Enfileira o job para cada tipo elegível. Devolve os tipos enfileirados.
      # Nunca levanta: reabastecer é conveniência, e falhar aqui não pode
      # derrubar a assinatura que acabou de dar certo.
      def enqueue_for(user:, doctor_profile:, only: nil)
        return [] if user.blank? || doctor_profile.blank?

        types = eligible_types(doctor_profile: doctor_profile, only: only)
        types.each do |sncr_type|
          AutoRefillJob.perform_later(
            user_id: user.id, doctor_profile_id: doctor_profile.id, sncr_type: sncr_type
          )
        end
        types
      rescue StandardError => e
        Rails.logger.warn(
          event: "sncr_auto_refill_enqueue_failed",
          error_class: e.class.name,
          error_message: e.message.to_s
        )
        []
      end

      def threshold_for(sncr_type)
        if NumberingBatch::ESPECIAL_TYPES.include?(sncr_type.to_s)
          Rails.application.config.x.sncr.refill_threshold_especial
        else
          Rails.application.config.x.sncr.refill_threshold_notificacao
        end
      end

      private

      def eligible?(doctor_profile:, sncr_type:, quota:, balance:, now:)
        return false unless used_before?(doctor_profile, sncr_type, now)
        return false if balance.fetch(sncr_type, 0) >= threshold_for(sncr_type)
        return false unless quota.allows?(sncr_type, origin: "auto_refill")
        return false if recently_requested?(doctor_profile, sncr_type, now)

        true
      end

      # Derivado do consumo, não de configuração: é mais preciso que a memória
      # do médico sobre o que ligou seis meses atrás. Um psiquiatra usa NRB e
      # RCE; puxar NRT porque existe geraria número parado.
      def used_before?(doctor_profile, sncr_type, now)
        ::SncrNumbering
          .consumed
          .for_doctor(doctor_profile)
          .of_type(sncr_type)
          .where(consumed_at: (now - USAGE_LOOKBACK)..)
          .exists?
      end

      def recently_requested?(doctor_profile, sncr_type, now)
        ::SncrNumberingRequest
          .for_doctor(doctor_profile)
          .of_type(sncr_type)
          .counts_against_quota
          .where(requested_at: (now - COOLDOWN)..)
          .exists?
      end
    end
  end
end
