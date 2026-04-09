class CreatePatients < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def change
    create_table :patients, id: :uuid do |t|
      t.string :full_name, null: false
      t.string :cpf, null: false
      t.date :birth_date, null: false
      t.string :email
      t.string :phone
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :patients, :cpf, unique: true
    add_index :patients, "lower(email)", unique: true, where: "email IS NOT NULL", name: "index_patients_on_lower_email"
    add_index :patients, :active

    add_check_constraint :patients,
                         "char_length(trim(full_name)) >= 3",
                         name: "chk_patients_full_name_length"
    add_check_constraint :patients,
                         "char_length(cpf) >= 11",
                         name: "chk_patients_cpf_length"
    add_check_constraint :patients,
                         "email IS NULL OR trim(email) <> ''",
                         name: "chk_patients_email_not_blank"
    add_check_constraint :patients,
                         "phone IS NULL OR char_length(regexp_replace(phone, '\\D', '', 'g')) >= 10",
                         name: "chk_patients_phone_digits_length"
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
