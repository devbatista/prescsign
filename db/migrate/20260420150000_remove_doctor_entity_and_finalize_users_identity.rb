class RemoveDoctorEntityAndFinalizeUsersIdentity < ActiveRecord::Migration[7.1]
  def up
    add_users_current_organization_reference!
    add_doctor_profile_identity_fields!
    backfill_from_legacy_doctors!
    remove_doctor_references!
    drop_legacy_mappings_and_doctors!
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "Doctor entity removal is irreversible"
  end

  private

  def add_users_current_organization_reference!
    return if column_exists?(:users, :current_organization_id)

    add_reference :users,
                  :current_organization,
                  type: :uuid,
                  foreign_key: { to_table: :organizations, on_delete: :nullify },
                  index: true,
                  null: true
  end

  def add_doctor_profile_identity_fields!
    add_column :doctor_profiles, :full_name, :string unless column_exists?(:doctor_profiles, :full_name)
    add_column :doctor_profiles, :email, :string unless column_exists?(:doctor_profiles, :email)
    add_column :doctor_profiles, :active, :boolean, null: false, default: true unless column_exists?(:doctor_profiles, :active)

    add_index :doctor_profiles, "lower(email)", unique: true, name: "idx_doctor_profiles_on_lower_email_unique" unless index_exists?(:doctor_profiles, "lower(email)", name: "idx_doctor_profiles_on_lower_email_unique")
  end

  def backfill_from_legacy_doctors!
    return unless table_exists?(:doctors)

    execute <<~SQL.squish
      UPDATE doctor_profiles AS dp
      SET full_name = COALESCE(dp.full_name, d.full_name),
          email = COALESCE(dp.email, d.email),
          active = COALESCE(dp.active, d.active),
          cpf = COALESCE(dp.cpf, d.cpf),
          license_number = COALESCE(dp.license_number, d.license_number),
          license_state = COALESCE(dp.license_state, d.license_state),
          specialty = COALESCE(dp.specialty, d.specialty)
      FROM doctors AS d
      WHERE dp.doctor_id = d.id
    SQL

    execute <<~SQL.squish
      UPDATE users AS u
      SET current_organization_id = d.current_organization_id
      FROM doctor_profiles AS dp
      INNER JOIN doctors AS d ON d.id = dp.doctor_id
      WHERE dp.user_id = u.id
        AND u.current_organization_id IS NULL
        AND d.current_organization_id IS NOT NULL
    SQL

    execute <<~SQL.squish
      UPDATE users AS u
      SET current_organization_id = memberships.organization_id
      FROM (
        SELECT DISTINCT ON (om.user_id) om.user_id, om.organization_id
        FROM organization_memberships AS om
        INNER JOIN organizations AS o ON o.id = om.organization_id
        WHERE om.status = 'active' AND o.active = TRUE
        ORDER BY om.user_id, om.created_at ASC
      ) AS memberships
      WHERE memberships.user_id = u.id
        AND u.current_organization_id IS NULL
    SQL
  end

  def remove_doctor_references!
    remove_reference_if_present(:auth_refresh_tokens, :doctor)
    remove_reference_if_present(:delivery_logs, :doctor)
    remove_reference_if_present(:documents, :doctor)
    remove_reference_if_present(:idempotency_keys, :doctor)
    remove_reference_if_present(:medical_certificates, :doctor)
    remove_reference_if_present(:organization_memberships, :doctor)
    remove_reference_if_present(:organization_responsibles, :doctor)
    remove_reference_if_present(:patients, :doctor)
    remove_reference_if_present(:prescriptions, :doctor)
    remove_reference_if_present(:doctor_profiles, :doctor)
  end

  def drop_legacy_mappings_and_doctors!
    drop_table :legacy_doctor_user_mappings, if_exists: true
    drop_table :doctors, if_exists: true
  end

  def remove_reference_if_present(table_name, reference_name)
    column_name = "#{reference_name}_id"
    return unless column_exists?(table_name, column_name)

    remove_reference table_name, reference_name, foreign_key: foreign_key_exists?(table_name, column: column_name)
  end
end
