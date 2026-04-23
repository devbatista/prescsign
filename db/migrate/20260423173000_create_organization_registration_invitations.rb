class CreateOrganizationRegistrationInvitations < ActiveRecord::Migration[7.1]
  def change
    create_table :organization_registration_invitations, id: :uuid do |t|
      t.uuid :organization_id, null: false
      t.uuid :invited_by_user_id
      t.string :invited_email, null: false
      t.string :token_digest, null: false
      t.datetime :expires_at, null: false
      t.datetime :accepted_at
      t.uuid :accepted_by_user_id

      t.timestamps
    end

    add_index :organization_registration_invitations, :token_digest, unique: true,
              name: "idx_org_registration_invitations_on_token_digest_unique"
    add_index :organization_registration_invitations,
              [:organization_id, :invited_email],
              name: "idx_org_registration_invitations_on_org_and_email"
    add_index :organization_registration_invitations,
              :accepted_at,
              name: "idx_org_registration_invitations_on_accepted_at"

    add_foreign_key :organization_registration_invitations, :organizations, on_delete: :cascade
    add_foreign_key :organization_registration_invitations, :users,
                    column: :invited_by_user_id, on_delete: :nullify
    add_foreign_key :organization_registration_invitations, :users,
                    column: :accepted_by_user_id, on_delete: :nullify
  end
end
