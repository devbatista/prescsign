class AddUserIdToCriticalTables < ActiveRecord::Migration[7.1]
  def up
    add_reference :organization_memberships, :user, type: :uuid, null: true, foreign_key: { on_delete: :restrict }
    add_reference :patients, :user, type: :uuid, null: true, foreign_key: { on_delete: :restrict }
    add_reference :prescriptions, :user, type: :uuid, null: true, foreign_key: { on_delete: :restrict }
    add_reference :medical_certificates, :user, type: :uuid, null: true, foreign_key: { on_delete: :restrict }
    add_reference :documents, :user, type: :uuid, null: true, foreign_key: { on_delete: :restrict }
    add_reference :delivery_logs, :user, type: :uuid, null: true, foreign_key: { on_delete: :nullify }
    add_reference :idempotency_keys, :user, type: :uuid, null: true, foreign_key: { on_delete: :cascade }

    add_index :organization_memberships, [:user_id, :organization_id], name: "idx_org_memberships_unique_user_org", unique: true
    add_index :organization_memberships, [:user_id, :status], name: "idx_org_memberships_user_status"
    add_index :patients, [:organization_id, :user_id], name: "idx_patients_on_organization_id_and_user_id"
    add_index :prescriptions, [:organization_id, :user_id], name: "idx_prescriptions_on_organization_id_and_user_id"
    add_index :medical_certificates, [:organization_id, :user_id], name: "idx_medical_certificates_on_organization_id_and_user_id"
    add_index :documents, [:organization_id, :user_id], name: "idx_documents_on_organization_id_and_user_id"
    add_index :delivery_logs, [:organization_id, :user_id], name: "idx_delivery_logs_on_organization_id_and_user_id"
    add_index :idempotency_keys, [:user_id, :organization_id, :scope, :key], name: "idx_idempotency_keys_user_uniqueness", unique: true

    ensure_users_for_existing_doctors!
    ensure_mappings_for_existing_doctors!
    ensure_user_roles_for_mapped_doctors!

    backfill_user_ids!

    change_column_null :organization_memberships, :user_id, false
    change_column_null :patients, :user_id, false
    change_column_null :prescriptions, :user_id, false
    change_column_null :medical_certificates, :user_id, false
    change_column_null :documents, :user_id, false
    change_column_null :idempotency_keys, :user_id, false
    change_column_null :auth_refresh_tokens, :user_id, false
  end

  def down
    change_column_null :auth_refresh_tokens, :user_id, true
    change_column_null :idempotency_keys, :user_id, true
    change_column_null :documents, :user_id, true
    change_column_null :medical_certificates, :user_id, true
    change_column_null :prescriptions, :user_id, true
    change_column_null :patients, :user_id, true
    change_column_null :organization_memberships, :user_id, true

    remove_index :idempotency_keys, name: "idx_idempotency_keys_user_uniqueness"
    remove_index :delivery_logs, name: "idx_delivery_logs_on_organization_id_and_user_id"
    remove_index :documents, name: "idx_documents_on_organization_id_and_user_id"
    remove_index :medical_certificates, name: "idx_medical_certificates_on_organization_id_and_user_id"
    remove_index :prescriptions, name: "idx_prescriptions_on_organization_id_and_user_id"
    remove_index :patients, name: "idx_patients_on_organization_id_and_user_id"
    remove_index :organization_memberships, name: "idx_org_memberships_user_status"
    remove_index :organization_memberships, name: "idx_org_memberships_unique_user_org"

    remove_reference :idempotency_keys, :user, foreign_key: true
    remove_reference :delivery_logs, :user, foreign_key: true
    remove_reference :documents, :user, foreign_key: true
    remove_reference :medical_certificates, :user, foreign_key: true
    remove_reference :prescriptions, :user, foreign_key: true
    remove_reference :patients, :user, foreign_key: true
    remove_reference :organization_memberships, :user, foreign_key: true
  end

  private

  def ensure_users_for_existing_doctors!
    execute <<~SQL
      INSERT INTO users (id, email, encrypted_password, status, created_at, updated_at)
      SELECT gen_random_uuid(),
             LOWER(d.email),
             COALESCE(d.encrypted_password, ''),
             CASE WHEN d.active THEN 'active' ELSE 'inactive' END,
             NOW(),
             NOW()
      FROM doctors d
      LEFT JOIN users u ON LOWER(u.email) = LOWER(d.email)
      WHERE u.id IS NULL
    SQL
  end

  def ensure_mappings_for_existing_doctors!
    execute <<~SQL
      INSERT INTO legacy_doctor_user_mappings (id, legacy_doctor_id, user_id, backfilled_at, created_at, updated_at)
      SELECT gen_random_uuid(), d.id, u.id, NOW(), NOW(), NOW()
      FROM doctors d
      INNER JOIN users u ON LOWER(u.email) = LOWER(d.email)
      LEFT JOIN legacy_doctor_user_mappings m ON m.legacy_doctor_id = d.id
      WHERE m.id IS NULL
    SQL
  end

  def ensure_user_roles_for_mapped_doctors!
    execute <<~SQL
      INSERT INTO user_roles (id, user_id, role, status, created_at, updated_at)
      SELECT gen_random_uuid(), m.user_id, 'doctor', 'active', NOW(), NOW()
      FROM legacy_doctor_user_mappings m
      LEFT JOIN user_roles ur ON ur.user_id = m.user_id AND ur.role = 'doctor'
      WHERE ur.id IS NULL
    SQL
  end

  def backfill_user_ids!
    %w[
      organization_memberships
      patients
      prescriptions
      medical_certificates
      documents
      delivery_logs
      idempotency_keys
      auth_refresh_tokens
    ].each do |table_name|
      execute <<~SQL
        UPDATE #{table_name} target
        SET user_id = map.user_id
        FROM legacy_doctor_user_mappings map
        WHERE target.doctor_id = map.legacy_doctor_id
          AND target.user_id IS NULL
      SQL
    end
  end
end
