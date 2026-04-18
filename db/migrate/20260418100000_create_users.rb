class CreateUsers < ActiveRecord::Migration[7.1]
  def change
    create_table :users, id: :uuid do |t|
      t.string :email, null: false
      t.string :encrypted_password, null: false, default: ""
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :users, "lower(email)", unique: true, name: "index_users_on_lower_email"
    add_index :users, :status

    add_check_constraint :users, "trim(email) <> ''", name: "chk_users_email_not_blank"
    add_check_constraint :users, "status IN ('active', 'inactive', 'blocked')", name: "chk_users_status_values"
  end
end
