class CreateAuditLogs < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def change
    create_table :audit_logs, id: :uuid do |t|
      t.string :actor_type
      t.uuid :actor_id
      t.uuid :patient_id
      t.uuid :document_id
      t.string :resource_type, null: false
      t.uuid :resource_id, null: false
      t.string :action, null: false
      t.jsonb :before_data, null: false, default: {}
      t.jsonb :after_data, null: false, default: {}
      t.string :request_id
      t.string :request_origin
      t.string :ip_address
      t.text :user_agent
      t.datetime :occurred_at, null: false, default: -> { "CURRENT_TIMESTAMP" }

      t.timestamps
    end

    add_index :audit_logs, %i[actor_type actor_id]
    add_index :audit_logs, :patient_id
    add_index :audit_logs, :document_id
    add_index :audit_logs, :action
    add_index :audit_logs, :request_id
    add_index :audit_logs, :occurred_at
    add_index :audit_logs, %i[resource_type resource_id]

    add_foreign_key :audit_logs, :patients, on_delete: :nullify
    add_foreign_key :audit_logs, :documents, on_delete: :nullify

    add_check_constraint :audit_logs,
                         "trim(action) <> ''",
                         name: "chk_audit_logs_action_not_blank"
    add_check_constraint :audit_logs,
                         "action IN ('created', 'updated', 'signed', 'sent', 'viewed', 'revoked', 'status_changed')",
                         name: "chk_audit_logs_action_values"
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
