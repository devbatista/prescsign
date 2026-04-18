class AddUserToAuditLogs < ActiveRecord::Migration[7.1]
  def up
    add_reference :audit_logs, :user, type: :uuid, null: true, foreign_key: { on_delete: :nullify }
    add_index :audit_logs, [:organization_id, :user_id, :occurred_at], name: "idx_audit_logs_on_organization_user_occurred_at"

    execute <<~SQL
      UPDATE audit_logs
      SET user_id = actor_id
      WHERE actor_type = 'User'
        AND user_id IS NULL
    SQL

    execute <<~SQL
      UPDATE audit_logs logs
      SET user_id = map.user_id
      FROM legacy_doctor_user_mappings map
      WHERE logs.actor_type = 'Doctor'
        AND logs.actor_id = map.legacy_doctor_id
        AND logs.user_id IS NULL
    SQL

    execute <<~SQL
      UPDATE audit_logs logs
      SET user_id = documents.user_id
      FROM documents
      WHERE logs.document_id = documents.id
        AND logs.user_id IS NULL
        AND documents.user_id IS NOT NULL
    SQL

    execute <<~SQL
      UPDATE audit_logs logs
      SET user_id = patients.user_id
      FROM patients
      WHERE logs.patient_id = patients.id
        AND logs.user_id IS NULL
        AND patients.user_id IS NOT NULL
    SQL
  end

  def down
    remove_index :audit_logs, name: "idx_audit_logs_on_organization_user_occurred_at"
    remove_reference :audit_logs, :user, foreign_key: true
  end
end
