class AddDeviseFieldsToDoctors < ActiveRecord::Migration[7.1]
  def change
    add_column :doctors, :encrypted_password, :string, null: false, default: "" unless column_exists?(:doctors, :encrypted_password)
    add_column :doctors, :reset_password_token, :string unless column_exists?(:doctors, :reset_password_token)
    add_column :doctors, :reset_password_sent_at, :datetime unless column_exists?(:doctors, :reset_password_sent_at)
    add_column :doctors, :remember_created_at, :datetime unless column_exists?(:doctors, :remember_created_at)

    add_index :doctors, :reset_password_token, unique: true unless index_exists?(:doctors, :reset_password_token)
  end
end
