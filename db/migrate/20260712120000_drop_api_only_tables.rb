class DropApiOnlyTables < ActiveRecord::Migration[7.1]
  # Fase 5: the JSON API (/api/v1) was removed. These tables backed JWT auth,
  # refresh tokens and header idempotency — all API-only. Dropped now that the
  # app is a session-based server-rendered monolith.
  def up
    drop_table :jwt_denylists, if_exists: true
    drop_table :auth_refresh_tokens, if_exists: true
    drop_table :idempotency_keys, if_exists: true
  end

  def down
    raise ActiveRecord::IrreversibleMigration, "API-only tables removed in Fase 5"
  end
end
