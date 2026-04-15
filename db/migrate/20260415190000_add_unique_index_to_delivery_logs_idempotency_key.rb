class AddUniqueIndexToDeliveryLogsIdempotencyKey < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    remove_index :delivery_logs, :idempotency_key if index_exists?(:delivery_logs, :idempotency_key)

    add_index :delivery_logs,
              :idempotency_key,
              unique: true,
              where: "idempotency_key IS NOT NULL",
              algorithm: :concurrently,
              name: "idx_delivery_logs_on_idempotency_key_unique"
  end

  def down
    remove_index :delivery_logs, name: "idx_delivery_logs_on_idempotency_key_unique" if index_exists?(:delivery_logs, name: "idx_delivery_logs_on_idempotency_key_unique")

    add_index :delivery_logs, :idempotency_key
  end
end
