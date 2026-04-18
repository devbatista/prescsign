class AddUserToAuthRefreshTokens < ActiveRecord::Migration[7.1]
  def change
    add_reference :auth_refresh_tokens, :user, type: :uuid, null: true, foreign_key: { on_delete: :nullify }
    add_index :auth_refresh_tokens, [:doctor_id, :user_id], name: "idx_auth_refresh_tokens_on_doctor_id_and_user_id"
  end
end
