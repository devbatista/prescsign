class RequireCpfOnDoctorProfiles < ActiveRecord::Migration[7.1]
  def up
    missing_count = select_value("SELECT COUNT(*) FROM doctor_profiles WHERE cpf IS NULL").to_i
    if missing_count.positive?
      raise ActiveRecord::IrreversibleMigration,
        "Preencha o CPF dos #{missing_count} perfis medicos antes de tornar doctor_profiles.cpf obrigatorio."
    end

    remove_check_constraint :doctor_profiles, name: "chk_doctor_profiles_cpf_length"
    add_check_constraint :doctor_profiles,
                         "char_length(cpf) >= 11",
                         name: "chk_doctor_profiles_cpf_length"
    change_column_null :doctor_profiles, :cpf, false
  end

  def down
    change_column_null :doctor_profiles, :cpf, true
    remove_check_constraint :doctor_profiles, name: "chk_doctor_profiles_cpf_length"
    add_check_constraint :doctor_profiles,
                         "cpf IS NULL OR char_length(cpf) >= 11",
                         name: "chk_doctor_profiles_cpf_length"
  end
end
