class AddSncrTypeToPrescriptions < ActiveRecord::Migration[7.1]
  SNCR_TYPES = %w[NRA NRB NRB2 NRR NRT RCE RET].freeze

  def change
    add_column :prescriptions, :sncr_type, :string

    add_check_constraint :prescriptions,
                         "sncr_type IS NULL OR sncr_type = ANY (ARRAY[#{SNCR_TYPES.map { |t| "'#{t}'" }.join(', ')}])",
                         name: "chk_prescriptions_sncr_type_values"

    add_index :prescriptions, :sncr_type,
              where: "sncr_type IS NOT NULL",
              name: "index_prescriptions_on_sncr_type"
  end
end
