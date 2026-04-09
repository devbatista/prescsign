class CreateDeliveryLogs < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def change
    create_table :delivery_logs, id: :uuid do |t|
      t.references :doctor, null: true, foreign_key: { on_delete: :nullify }, type: :uuid
      t.references :patient, null: true, foreign_key: { on_delete: :nullify }, type: :uuid
      t.references :document, null: true, foreign_key: { on_delete: :nullify }, type: :uuid
      t.string :channel, null: false
      t.string :status, null: false, default: "queued"
      t.integer :attempt_number, null: false, default: 1
      t.string :provider_name
      t.string :provider_message_id
      t.string :recipient
      t.string :error_code
      t.text :error_message
      t.datetime :attempted_at, null: false, default: -> { "CURRENT_TIMESTAMP" }
      t.datetime :delivered_at
      t.string :request_id
      t.string :idempotency_key
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :delivery_logs, :channel
    add_index :delivery_logs, :status
    add_index :delivery_logs, :attempted_at
    add_index :delivery_logs, :request_id
    add_index :delivery_logs, :idempotency_key
    add_index :delivery_logs, %i[doctor_id patient_id]
    add_index :delivery_logs, %i[document_id status]
    add_index :delivery_logs, %i[channel status attempted_at], name: "idx_delivery_logs_channel_status_attempted_at"

    add_check_constraint :delivery_logs,
                         "channel IN ('email', 'sms', 'whatsapp')",
                         name: "chk_delivery_logs_channel_values"
    add_check_constraint :delivery_logs,
                         "status IN ('queued', 'processing', 'sent', 'delivered', 'failed')",
                         name: "chk_delivery_logs_status_values"
    add_check_constraint :delivery_logs,
                         "attempt_number >= 1",
                         name: "chk_delivery_logs_attempt_number_gte_one"
    add_check_constraint :delivery_logs,
                         "status <> 'delivered' OR delivered_at IS NOT NULL",
                         name: "chk_delivery_logs_delivered_requires_delivered_at"
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
