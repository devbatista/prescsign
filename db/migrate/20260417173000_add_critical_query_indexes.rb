class AddCriticalQueryIndexes < ActiveRecord::Migration[7.1]
  def change
    add_index :patients, %i[organization_id doctor_id], name: "idx_patients_on_organization_id_and_doctor_id"
    add_index :documents, %i[organization_id doctor_id], name: "idx_documents_on_organization_id_and_doctor_id"
    add_index :prescriptions, %i[organization_id doctor_id], name: "idx_prescriptions_on_organization_id_and_doctor_id"
    add_index :medical_certificates, %i[organization_id doctor_id], name: "idx_medical_certificates_on_organization_id_and_doctor_id"

    add_index :audit_logs, %i[organization_id document_id occurred_at], name: "idx_audit_logs_on_organization_document_occurred_at"
    add_index :audit_logs, %i[organization_id patient_id occurred_at], name: "idx_audit_logs_on_organization_patient_occurred_at"
    add_index :audit_logs, %i[organization_id actor_type actor_id occurred_at], name: "idx_audit_logs_on_organization_actor_occurred_at"
  end
end
