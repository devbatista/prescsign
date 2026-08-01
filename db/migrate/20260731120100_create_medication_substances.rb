class CreateMedicationSubstances < ActiveRecord::Migration[7.1]
  def change
    # Junção N:N entre catálogo de produtos (medications) e substâncias ativas.
    # Um produto pode ter mais de uma substância (associações); uma substância
    # aparece em vários produtos.
    create_table :medication_substances, id: :uuid do |t|
      t.references :medication, type: :uuid, null: false,
                   foreign_key: { on_delete: :cascade }, index: false
      t.references :substance, type: :uuid, null: false,
                   foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    # Índice composto único cobre também as buscas por medication_id (prefixo).
    add_index :medication_substances, %i[medication_id substance_id],
              unique: true, name: "idx_medication_substances_unique_pair"
  end
end
