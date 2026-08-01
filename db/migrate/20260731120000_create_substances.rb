class CreateSubstances < ActiveRecord::Migration[7.1]
  def change
    create_table :substances, id: :uuid do |t|
      t.string :name, null: false
      t.string :list_344 # lista da Portaria 344/98 e afins (referência/auditoria)
      t.string :sncr_type # tipo SNCR derivado (acionável); nil = não controlada
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    # Nome canônico único (case-insensitive): a mesma substância não deve existir
    # em duas grafias.
    add_index :substances, "LOWER(name)", unique: true, name: "index_substances_on_lower_name"
    add_index :substances, :sncr_type,
              where: "sncr_type IS NOT NULL",
              name: "index_substances_on_sncr_type"

    add_check_constraint :substances,
                         "TRIM(BOTH FROM name) <> ''",
                         name: "chk_substances_name_present"
    add_check_constraint :substances,
                         "sncr_type IS NULL OR sncr_type IN ('NRA','NRB','NRB2','NRR','NRT','RCE','RET')",
                         name: "chk_substances_sncr_type_values"
  end
end
