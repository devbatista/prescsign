class CreateAuthRefreshTokens < ActiveRecord::Migration[7.1]
  def change
    create_table :auth_refresh_tokens, id: :uuid, if_not_exists: true do |t|
      t.references :doctor, null: false, foreign_key: { on_delete: :cascade }, type: :uuid
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :revoked_at

      t.timestamps
    end

    add_index :auth_refresh_tokens, :token_digest, unique: true, if_not_exists: true
    add_index :auth_refresh_tokens, :expires_at, if_not_exists: true
    add_index :auth_refresh_tokens, :revoked_at, if_not_exists: true
    add_index :auth_refresh_tokens, %i[doctor_id revoked_at], if_not_exists: true

    return if check_constraint_exists?(:auth_refresh_tokens, name: "chk_auth_refresh_tokens_token_digest_not_blank")

    add_check_constraint :auth_refresh_tokens,
                         "trim(token_digest) <> ''",
                         name: "chk_auth_refresh_tokens_token_digest_not_blank"
  end
end
