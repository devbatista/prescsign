class ScopePatientEmailUniquenessByOrganization < ActiveRecord::Migration[7.1]
  GLOBAL_EMAIL_INDEX = "index_patients_on_lower_email".freeze
  SCOPED_EMAIL_INDEX = "idx_patients_on_organization_id_and_lower_email_unique".freeze

  def up
    remove_index :patients, name: GLOBAL_EMAIL_INDEX if index_name_exists?(:patients, GLOBAL_EMAIL_INDEX)

    add_index :patients,
              "organization_id, lower(email)",
              unique: true,
              where: "email IS NOT NULL",
              name: SCOPED_EMAIL_INDEX
  end

  def down
    remove_index :patients, name: SCOPED_EMAIL_INDEX if index_name_exists?(:patients, SCOPED_EMAIL_INDEX)

    add_index :patients,
              "lower(email)",
              unique: true,
              where: "email IS NOT NULL",
              name: GLOBAL_EMAIL_INDEX
  end
end
