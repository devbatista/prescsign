class CreateUserRoles < ActiveRecord::Migration[7.1]
  def change
    create_table :user_roles, id: :uuid do |t|
      t.references :user, null: false, type: :uuid, foreign_key: { on_delete: :cascade }
      t.string :role, null: false
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :user_roles, %i[user_id role], unique: true, name: "idx_user_roles_on_user_id_and_role_unique"
    add_index :user_roles, %i[role status], name: "idx_user_roles_on_role_and_status"

    add_check_constraint :user_roles,
                         "role IN ('doctor', 'admin', 'support', 'manager', 'super_admin')",
                         name: "chk_user_roles_role_values"
    add_check_constraint :user_roles, "status IN ('active', 'inactive')", name: "chk_user_roles_status_values"
  end
end
