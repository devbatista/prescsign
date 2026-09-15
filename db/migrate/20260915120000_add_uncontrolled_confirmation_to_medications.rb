class AddUncontrolledConfirmationToMedications < ActiveRecord::Migration[8.1]
  def change
    # Curadoria: o back-office confirma que a tarja de controlado publicada pela
    # CMED não corresponde a substância controlada (Portaria 344/98 / IN 360).
    # É a saída para o ruído da fila de revisão — eletrólitos, glicose,
    # enoxaparina, montelucaste, fluconazol — que hoje não tem resolução
    # durável: vincular substância seria errado, e trocar a tarja é desfeito
    # pela reimportação mensal da CMED, que sobrescreve `control_class`.
    #
    # Estes três campos são do back-office e o import NÃO os toca (ver
    # Medications::CmedCatalogImport#attributes_for). Guarda o instante, não um
    # booleano, pelo mesmo motivo de PrescriptionItem#uncontrolled_confirmed_at:
    # a auditoria precisa saber quando — e, sem audit log no admin, quem.
    add_column :medications, :uncontrolled_confirmed_at, :datetime
    add_column :medications, :uncontrolled_confirmed_reason, :string
    add_column :medications, :uncontrolled_confirmed_by_id, :uuid

    add_index :medications, :uncontrolled_confirmed_by_id,
              name: "index_medications_on_uncontrolled_confirmed_by_id"
    add_foreign_key :medications, :users,
                    column: :uncontrolled_confirmed_by_id, on_delete: :nullify

    # Confirmação sem motivo é afirmação regulatória sem justificativa; motivo
    # sem confirmação é lixo. Ou ambos ou nenhum. Quem confirmou fica fora da
    # regra porque some se o usuário for removido (on_delete: :nullify).
    add_check_constraint :medications,
                         "(uncontrolled_confirmed_at IS NULL) = (uncontrolled_confirmed_reason IS NULL)",
                         name: "chk_medications_uncontrolled_confirmation_consistency"
  end
end
