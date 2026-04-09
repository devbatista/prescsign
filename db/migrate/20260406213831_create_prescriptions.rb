class CreatePrescriptions < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def change
    create_table :prescriptions, id: :uuid do |t|
      t.references :doctor, null: false, foreign_key: true, type: :uuid
      t.references :patient, null: false, foreign_key: true, type: :uuid
      t.string :code, null: false
      t.text :content, null: false
      t.date :issued_on, null: false
      t.date :valid_until
      t.string :status, null: false, default: "draft"

      t.timestamps
    end

    add_index :prescriptions, :code, unique: true
    add_index :prescriptions, :issued_on
    add_index :prescriptions, :status
    add_index :prescriptions, %i[doctor_id patient_id]

    add_check_constraint :prescriptions,
                         "trim(code) <> ''",
                         name: "chk_prescriptions_code_not_blank"
    add_check_constraint :prescriptions,
                         "char_length(trim(code)) >= 8",
                         name: "chk_prescriptions_code_length"
    add_check_constraint :prescriptions,
                         "trim(content) <> ''",
                         name: "chk_prescriptions_content_not_blank"
    add_check_constraint :prescriptions,
                         "status IN ('draft', 'signed', 'cancelled')",
                         name: "chk_prescriptions_status_values"
    add_check_constraint :prescriptions,
                         "valid_until IS NULL OR valid_until >= issued_on",
                         name: "chk_prescriptions_valid_until_gte_issued_on"
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
