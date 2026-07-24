class CreateSncrNumberings < ActiveRecord::Migration[7.1]
  SNCR_TYPES = %w[NRA NRB NRB2 NRR NRT RCE RET].freeze
  STATUSES = %w[available consumed].freeze

  def change
    create_table :sncr_numberings, id: :uuid do |t|
      t.uuid :doctor_profile_id, null: false
      t.uuid :prescription_id
      t.string :sncr_type, null: false
      t.string :number, null: false
      t.string :status, null: false, default: "available"
      t.datetime :obtained_at, null: false
      t.datetime :consumed_at

      t.timestamps
    end

    add_index :sncr_numberings, :number, unique: true,
              name: "index_sncr_numberings_on_number"
    add_index :sncr_numberings, [ :doctor_profile_id, :sncr_type, :status ],
              name: "index_sncr_numberings_on_owner_type_status"
    add_index :sncr_numberings, :prescription_id,
              name: "index_sncr_numberings_on_prescription_id"

    add_foreign_key :sncr_numberings, :doctor_profiles, on_delete: :cascade
    add_foreign_key :sncr_numberings, :prescriptions, on_delete: :restrict

    add_check_constraint :sncr_numberings,
                         "sncr_type = ANY (ARRAY[#{SNCR_TYPES.map { |t| "'#{t}'" }.join(', ')}])",
                         name: "chk_sncr_numberings_type_values"
    add_check_constraint :sncr_numberings,
                         "status = ANY (ARRAY[#{STATUSES.map { |s| "'#{s}'" }.join(', ')}])",
                         name: "chk_sncr_numberings_status_values"
    add_check_constraint :sncr_numberings,
                         "TRIM(BOTH FROM number) <> ''",
                         name: "chk_sncr_numberings_number_not_blank"
    # Coerencia: consumido <=> tem receita e consumed_at; disponivel <=> ambos nulos.
    add_check_constraint :sncr_numberings,
                         "(status = 'consumed' AND prescription_id IS NOT NULL AND consumed_at IS NOT NULL) " \
                         "OR (status = 'available' AND prescription_id IS NULL AND consumed_at IS NULL)",
                         name: "chk_sncr_numberings_consumption_consistency"
  end
end
