class ScopeDoctorProfileLicenseLookupByOrganization < ActiveRecord::Migration[7.1]
  def change
    remove_index :doctor_profiles, name: "idx_doctor_profiles_on_license_unique"
    add_index :doctor_profiles,
      %i[license_number license_state],
      name: "idx_doctor_profiles_on_license_lookup"
  end
end
