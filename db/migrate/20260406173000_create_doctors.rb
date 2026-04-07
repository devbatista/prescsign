class CreateDoctors < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def change
    create_table :doctors do |t|
      t.string :full_name, null: false
      t.string :email, null: false
      t.string :cpf, null: false
      t.string :license_number, null: false
      t.string :license_state, null: false, limit: 2
      t.string :specialty
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :doctors, "lower(email)", unique: true, name: "index_doctors_on_lower_email"
    add_index :doctors, :cpf, unique: true
    add_index :doctors, %i[license_number license_state], unique: true
    add_index :doctors, :active

    add_check_constraint :doctors,
                         "char_length(trim(full_name)) >= 3",
                         name: "chk_doctors_full_name_length"
    add_check_constraint :doctors, "trim(email) <> ''", name: "chk_doctors_email_not_blank"
    add_check_constraint :doctors, "char_length(cpf) >= 11", name: "chk_doctors_cpf_length"
    add_check_constraint :doctors,
                         "char_length(trim(license_number)) >= 4",
                         name: "chk_doctors_license_number_length"
    add_check_constraint :doctors,
                         "char_length(license_state) = 2",
                         name: "chk_doctors_license_state_length"
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
