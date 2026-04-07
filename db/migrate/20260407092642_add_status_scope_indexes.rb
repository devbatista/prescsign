class AddStatusScopeIndexes < ActiveRecord::Migration[7.1]
  def change
    add_index :prescriptions, %i[doctor_id status], name: "idx_prescriptions_on_doctor_id_and_status"
    add_index :prescriptions, %i[patient_id status], name: "idx_prescriptions_on_patient_id_and_status"

    add_index :medical_certificates, %i[doctor_id status], name: "idx_medical_certificates_on_doctor_id_and_status"
    add_index :medical_certificates, %i[patient_id status], name: "idx_medical_certificates_on_patient_id_and_status"

    add_index :documents, %i[doctor_id status], name: "idx_documents_on_doctor_id_and_status"
    add_index :documents, %i[patient_id status], name: "idx_documents_on_patient_id_and_status"

    add_index :delivery_logs, %i[doctor_id status], name: "idx_delivery_logs_on_doctor_id_and_status"
    add_index :delivery_logs, %i[patient_id status], name: "idx_delivery_logs_on_patient_id_and_status"
  end
end
