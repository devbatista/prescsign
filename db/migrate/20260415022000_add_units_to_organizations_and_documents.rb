class AddUnitsToOrganizationsAndDocuments < ActiveRecord::Migration[7.1]
  class MigrationOrganization < ActiveRecord::Base
    self.table_name = "organizations"
  end

  class MigrationUnit < ActiveRecord::Base
    self.table_name = "units"
  end

  def up
    create_table :units, id: :uuid do |t|
      t.references :organization, null: false, type: :uuid, foreign_key: { on_delete: :restrict }
      t.string :name, null: false
      t.string :code
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :units, %i[organization_id name], unique: true, name: "idx_units_on_organization_id_and_name"
    add_index :units, %i[organization_id active], name: "idx_units_on_organization_id_and_active"
    add_check_constraint :units, "trim(name) <> ''", name: "chk_units_name_not_blank"

    add_reference :documents, :unit, type: :uuid, foreign_key: { on_delete: :restrict }
    add_reference :audit_logs, :unit, type: :uuid, foreign_key: { on_delete: :nullify }

    MigrationOrganization.find_each do |organization|
      unit = MigrationUnit.create!(
        organization_id: organization.id,
        name: "Principal",
        code: "HQ",
        active: true
      )

      execute <<~SQL.squish
        UPDATE documents
        SET unit_id = '#{unit.id}'
        WHERE organization_id = '#{organization.id}'
          AND unit_id IS NULL
      SQL
    end

    change_column_null :documents, :unit_id, false
    add_index :documents, %i[organization_id unit_id], name: "idx_documents_on_organization_id_and_unit_id"
    add_index :audit_logs, %i[organization_id unit_id], name: "idx_audit_logs_on_organization_id_and_unit_id"
  end

  def down
    remove_index :audit_logs, name: "idx_audit_logs_on_organization_id_and_unit_id"
    remove_index :documents, name: "idx_documents_on_organization_id_and_unit_id"
    change_column_null :documents, :unit_id, true

    remove_reference :audit_logs, :unit, type: :uuid, foreign_key: true
    remove_reference :documents, :unit, type: :uuid, foreign_key: true

    drop_table :units
  end
end
