module Sncr
  # Garante que uma receita controlada tenha uma numeração SNCR consumida do pool
  # do prescritor. É o "portão" chamado na assinatura (dentro da transação de
  # Documents::SigningService): se a receita é controlada e ainda não tem número,
  # consome o próximo do pool; se o pool do tipo está vazio, `SncrNumbering::
  # PoolEmpty` propaga e a assinatura inteira faz rollback (número não é gasto).
  #
  # No-op para documentos não controlados (receita comum, atestado etc.) e
  # idempotente (se já houver numeração vinculada, não consome outra).
  class NumberingAssignment
    def self.ensure_for!(documentable)
      return unless documentable.is_a?(::Prescription)
      return unless documentable.controlled?
      return documentable.sncr_numbering if documentable.sncr_numbering.present?

      doctor_profile = documentable.user&.doctor_profile
      if doctor_profile.nil?
        raise ::Sncr::Error, "Receita controlada exige um prescritor com perfil de médico (CPF)."
      end

      ::SncrNumbering.consume_next!(
        doctor_profile: doctor_profile,
        sncr_type: documentable.sncr_type,
        prescription: documentable
      )
    end
  end
end
