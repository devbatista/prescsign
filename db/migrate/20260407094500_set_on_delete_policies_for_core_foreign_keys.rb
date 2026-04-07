class SetOnDeletePoliciesForCoreForeignKeys < ActiveRecord::Migration[7.1]
  def change
    replace_fk :prescriptions, :doctors, :doctor_id, :restrict
    replace_fk :prescriptions, :patients, :patient_id, :restrict

    replace_fk :medical_certificates, :doctors, :doctor_id, :restrict
    replace_fk :medical_certificates, :patients, :patient_id, :restrict

    replace_fk :documents, :doctors, :doctor_id, :restrict
    replace_fk :documents, :patients, :patient_id, :restrict

    replace_fk :document_versions, :documents, :document_id, :cascade
  end

  private

  def replace_fk(from_table, to_table, column, on_delete)
    remove_foreign_key from_table, column: column
    add_foreign_key from_table, to_table, column: column, on_delete: on_delete
  end
end
