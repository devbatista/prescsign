class AddGenderToDoctorProfiles < ActiveRecord::Migration[7.1]
  def up
    return if column_exists?(:doctor_profiles, :gender)

    add_column :doctor_profiles, :gender, :string
    add_check_constraint :doctor_profiles,
                         "gender IS NULL OR gender IN ('male', 'female')",
                         name: "chk_doctor_profiles_gender_values"
  end

  def down
    remove_check_constraint :doctor_profiles,
                            name: "chk_doctor_profiles_gender_values",
                            if_exists: true
    remove_column :doctor_profiles, :gender if column_exists?(:doctor_profiles, :gender)
  end
end
