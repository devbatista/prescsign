class AddDoctorToOrganizationResponsibles < ActiveRecord::Migration[7.1]
  def change
    add_reference :organization_responsibles,
                  :doctor,
                  type: :uuid,
                  foreign_key: { on_delete: :nullify },
                  null: true

    add_index :organization_responsibles,
              %i[organization_id doctor_id],
              name: "idx_org_responsibles_on_org_id_and_doctor_id"
  end
end
