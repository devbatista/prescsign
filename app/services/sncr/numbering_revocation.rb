module Sncr
  # Marca a numeração SNCR cujo documento foi revogado. Contraparte do
  # Sncr::NumberingAssignment: um consome o número na assinatura, o outro
  # registra o destino quando o documento cai.
  #
  # Chamado nos DOIS caminhos de revogação — Documents::LifecycleService#revoke!
  # (o médico revoga) e Documents::IntegrityService#revoke_for_integrity! (o
  # sistema revoga ao detectar adulteração do PDF). Corrigir só o primeiro
  # deixaria sem rastro justamente o caso adversarial.
  #
  # O que este serviço NÃO faz, e por quê:
  #
  #   - **não devolve o número ao pool.** Ver o comentário da migration
  #     20260914120000. Resumo: o número já foi impresso numa receita assinada e
  #     é único nacionalmente; reusá-lo criaria dois documentos com o mesmo
  #     número.
  #   - **não comunica o cancelamento à Anvisa.** Não existe endpoint: o Manual
  #     da API SNCR 1ª ed. (jun/2026) cobre apenas /auth/login, /auth/token e os
  #     dois de numeração. Isso é bloqueador externo (§9 de
  #     docs/sncr/SNCR_INTEGRATION.md), não lacuna de código nossa.
  class NumberingRevocation
    def self.revoke_for!(documentable, at: Time.current)
      new(documentable, at: at).call
    end

    def initialize(documentable, at: Time.current)
      @documentable = documentable
      @at = at
    end

    # Retorna a numeração marcada, ou nil quando não há o que marcar (documento
    # sem numeração — receita comum, atestado — ou já marcado antes).
    def call
      return nil unless @documentable.is_a?(::Prescription)

      numbering = @documentable.sncr_numbering
      return nil if numbering.nil?
      # Idempotente: revogar duas vezes preserva a data do primeiro registro, que
      # é a que vale para a auditoria.
      return nil if numbering.revoked_at.present?

      numbering.update!(revoked_at: @at)
      numbering
    end
  end
end
