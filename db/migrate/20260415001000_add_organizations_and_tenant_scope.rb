class AddOrganizationsAndTenantScope < ActiveRecord::Migration[7.1]
  class MigrationDoctor < ActiveRecord::Base
    self.table_name = "doctors"
  end

  class MigrationOrganization < ActiveRecord::Base
    self.table_name = "organizations"
  end

  class MigrationOrganizationMembership < ActiveRecord::Base
    self.table_name = "organization_memberships"
  end

  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def up
    create_table :organizations, id: :uuid do |t|
      t.string :name, null: false
      t.string :kind, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :organizations, :kind
    add_index :organizations, :active
    add_check_constraint :organizations,
                         "trim(name) <> ''",
                         name: "chk_organizations_name_not_blank"
    add_check_constraint :organizations,
                         "kind IN ('autonomo', 'clinica', 'hospital')",
                         name: "chk_organizations_kind_values"

    create_table :organization_memberships, id: :uuid do |t|
      t.references :doctor, null: false, type: :uuid, foreign_key: { on_delete: :restrict }
      t.references :organization, null: false, type: :uuid, foreign_key: { on_delete: :restrict }
      t.string :role, null: false
      t.string :status, null: false, default: "active"

      t.timestamps
    end

    add_index :organization_memberships, %i[doctor_id organization_id],
              unique: true,
              name: "idx_org_memberships_unique_doctor_org"
    add_index :organization_memberships, %i[organization_id role],
              name: "idx_org_memberships_org_role"
    add_index :organization_memberships, %i[doctor_id status],
              name: "idx_org_memberships_doctor_status"
    add_check_constraint :organization_memberships,
                         "role IN ('owner', 'admin', 'doctor', 'staff')",
                         name: "chk_organization_memberships_role_values"
    add_check_constraint :organization_memberships,
                         "status IN ('active', 'inactive')",
                         name: "chk_organization_memberships_status_values"

    add_reference :doctors,
                  :current_organization,
                  type: :uuid,
                  foreign_key: { to_table: :organizations, on_delete: :nullify }

    add_reference :patients, :organization, type: :uuid, foreign_key: { on_delete: :restrict }
    add_reference :prescriptions, :organization, type: :uuid, foreign_key: { on_delete: :restrict }
    add_reference :medical_certificates, :organization, type: :uuid, foreign_key: { on_delete: :restrict }
    add_reference :documents, :organization, type: :uuid, foreign_key: { on_delete: :restrict }
    add_reference :audit_logs, :organization, type: :uuid, foreign_key: { on_delete: :nullify }
    add_reference :delivery_logs, :organization, type: :uuid, foreign_key: { on_delete: :nullify }

    add_index :patients, %i[organization_id full_name], name: "idx_patients_on_organization_id_and_full_name"
    add_index :prescriptions, %i[organization_id status], name: "idx_prescriptions_on_organization_id_and_status"
    add_index :medical_certificates,
              %i[organization_id status],
              name: "idx_medical_certificates_on_organization_id_and_status"
    add_index :documents, %i[organization_id status], name: "idx_documents_on_organization_id_and_status"
    add_index :audit_logs, %i[organization_id occurred_at], name: "idx_audit_logs_on_organization_id_and_occurred_at"
    add_index :delivery_logs, %i[organization_id status], name: "idx_delivery_logs_on_organization_id_and_status"

    MigrationDoctor.find_each do |doctor|
      organization = MigrationOrganization.create!(
        name: "Autônomo - #{doctor.full_name}",
        kind: "autonomo",
        active: true
      )

      MigrationOrganizationMembership.create!(
        doctor_id: doctor.id,
        organization_id: organization.id,
        role: "owner",
        status: "active"
      )

      doctor.update_columns(current_organization_id: organization.id)
    end

    execute <<~SQL.squish
      UPDATE patients p
      SET organization_id = d.current_organization_id
      FROM doctors d
      WHERE p.doctor_id = d.id
        AND p.organization_id IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE prescriptions p
      SET organization_id = d.current_organization_id
      FROM doctors d
      WHERE p.doctor_id = d.id
        AND p.organization_id IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE medical_certificates mc
      SET organization_id = d.current_organization_id
      FROM doctors d
      WHERE mc.doctor_id = d.id
        AND mc.organization_id IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE documents doc
      SET organization_id = d.current_organization_id
      FROM doctors d
      WHERE doc.doctor_id = d.id
        AND doc.organization_id IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE audit_logs al
      SET organization_id = d.current_organization_id
      FROM doctors d
      WHERE al.actor_type = 'Doctor'
        AND al.actor_id = d.id
        AND al.organization_id IS NULL
    SQL

    execute <<~SQL.squish
      UPDATE delivery_logs dl
      SET organization_id = d.current_organization_id
      FROM doctors d
      WHERE dl.doctor_id = d.id
        AND dl.organization_id IS NULL
    SQL

    remove_index :patients, :cpf
    remove_index :patients, name: "idx_patients_on_doctor_id_and_cpf_unique"
    add_index :patients, %i[organization_id cpf], unique: true, name: "idx_patients_on_organization_id_and_cpf_unique"

    change_column_null :patients, :organization_id, false
    change_column_null :prescriptions, :organization_id, false
    change_column_null :medical_certificates, :organization_id, false
    change_column_null :documents, :organization_id, false
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength

  def down
    change_column_null :documents, :organization_id, true
    change_column_null :medical_certificates, :organization_id, true
    change_column_null :prescriptions, :organization_id, true
    change_column_null :patients, :organization_id, true

    remove_index :patients, name: "idx_patients_on_organization_id_and_cpf_unique"
    add_index :patients, :cpf, unique: true
    add_index :patients, %i[doctor_id cpf], unique: true, name: "idx_patients_on_doctor_id_and_cpf_unique"

    remove_index :audit_logs, name: "idx_audit_logs_on_organization_id_and_occurred_at"
    remove_index :delivery_logs, name: "idx_delivery_logs_on_organization_id_and_status"
    remove_index :documents, name: "idx_documents_on_organization_id_and_status"
    remove_index :medical_certificates, name: "idx_medical_certificates_on_organization_id_and_status"
    remove_index :prescriptions, name: "idx_prescriptions_on_organization_id_and_status"
    remove_index :patients, name: "idx_patients_on_organization_id_and_full_name"

    remove_reference :delivery_logs, :organization, type: :uuid, foreign_key: true
    remove_reference :audit_logs, :organization, type: :uuid, foreign_key: true
    remove_reference :documents, :organization, type: :uuid, foreign_key: true
    remove_reference :medical_certificates, :organization, type: :uuid, foreign_key: true
    remove_reference :prescriptions, :organization, type: :uuid, foreign_key: true
    remove_reference :patients, :organization, type: :uuid, foreign_key: true
    remove_reference :doctors, :current_organization, type: :uuid, foreign_key: true

    drop_table :organization_memberships
    drop_table :organizations
  end
end
