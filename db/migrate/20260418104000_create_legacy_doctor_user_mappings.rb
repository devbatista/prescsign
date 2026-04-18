class CreateLegacyDoctorUserMappings < ActiveRecord::Migration[7.1]
  def change
    create_table :legacy_doctor_user_mappings, id: :uuid do |t|
      t.uuid :legacy_doctor_id, null: false
      t.uuid :user_id, null: false
      t.datetime :backfilled_at, null: false

      t.timestamps
    end

    add_index :legacy_doctor_user_mappings, :legacy_doctor_id, unique: true
    add_index :legacy_doctor_user_mappings, :user_id

    add_foreign_key :legacy_doctor_user_mappings, :doctors,
                    column: :legacy_doctor_id,
                    on_delete: :cascade
    add_foreign_key :legacy_doctor_user_mappings, :users, on_delete: :cascade
  end
end
