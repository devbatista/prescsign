class CreateDoctorProfiles < ActiveRecord::Migration[7.1]
  def change
    create_table :doctor_profiles, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :doctor, null: true, type: :uuid, foreign_key: { on_delete: :nullify }
      t.string :cpf
      t.string :license_number, null: false
      t.string :license_state, null: false, limit: 2
      t.string :specialty

      t.timestamps
    end

    add_index :doctor_profiles, :cpf, unique: true, where: "cpf IS NOT NULL"
    add_index :doctor_profiles, %i[license_number license_state], unique: true, name: "idx_doctor_profiles_on_license_unique"

    add_check_constraint :doctor_profiles,
                         "cpf IS NULL OR char_length(cpf) >= 11",
                         name: "chk_doctor_profiles_cpf_length"
    add_check_constraint :doctor_profiles,
                         "char_length(license_state) = 2",
                         name: "chk_doctor_profiles_license_state_length"
    add_check_constraint :doctor_profiles,
                         "trim(license_number) <> ''",
                         name: "chk_doctor_profiles_license_number_not_blank"
  end
end
