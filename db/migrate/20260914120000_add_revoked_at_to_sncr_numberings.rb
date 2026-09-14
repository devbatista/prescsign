class AddRevokedAtToSncrNumberings < ActiveRecord::Migration[8.1]
  def change
    # Registra que o documento que consumiu este número foi revogado — pela mão
    # do médico (Documents::LifecycleService#revoke!) ou pela detecção de
    # adulteração (Documents::IntegrityService#revoke_for_integrity!).
    #
    # O número NÃO volta ao pool, e isso é decisão, não omissão: ele é consumido
    # dentro da transação da assinatura, então "consumido" significa que existe
    # um documento assinado no mundo com aquele número nacional impresso —
    # possivelmente já entregue ao paciente. Devolvê-lo ao pool faria a próxima
    # receita sair com o mesmo número nacional. Por isso o status permanece
    # "consumed": a revogação é um fato sobre o documento, não uma devolução.
    add_column :sncr_numberings, :revoked_at, :datetime

    # Índice parcial: a pergunta útil é "quais números morreram", nunca "quais
    # não morreram". Quando/se a Anvisa publicar um endpoint de cancelamento —
    # o Manual 1ª ed. (jun/2026) não tem nenhum —, esta é a fila de backfill.
    add_index :sncr_numberings, :revoked_at,
              name: "index_sncr_numberings_on_revoked_at",
              where: "revoked_at IS NOT NULL"

    # Número disponível nunca esteve numa receita, logo não há o que revogar.
    add_check_constraint :sncr_numberings,
                         "revoked_at IS NULL OR status::text = 'consumed'::text",
                         name: "chk_sncr_numberings_revoked_only_when_consumed"
  end
end
