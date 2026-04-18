class CreateOrganizationResponsibles < ActiveRecord::Migration[7.1]
  def change
    create_table :organization_responsibles, id: :uuid do |t|
      t.references :organization, null: false, type: :uuid, foreign_key: { on_delete: :restrict }

      t.timestamps
    end

    add_index :organization_responsibles, %i[organization_id created_at], name: "idx_org_responsibles_on_org_id_and_created_at"
  end
end
