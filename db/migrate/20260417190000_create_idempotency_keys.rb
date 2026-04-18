class CreateIdempotencyKeys < ActiveRecord::Migration[7.1]
  def change
    create_table :idempotency_keys, id: :uuid do |t|
      t.references :doctor, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.references :organization, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :scope, null: false
      t.string :key, null: false
      t.string :request_fingerprint, null: false
      t.integer :status_code
      t.jsonb :response_body, null: false, default: {}

      t.timestamps
    end

    add_index :idempotency_keys, %i[doctor_id organization_id scope key],
              unique: true,
              name: "idx_idempotency_keys_uniqueness"
    add_index :idempotency_keys, :created_at
  end
end
