class AddIntegrityConstraintsToDocumentsAndDeliveryLogs < ActiveRecord::Migration[7.1]
  def change
    add_check_constraint :documents,
                         "(kind = 'prescription' AND documentable_type = 'Prescription') OR "\
                         "(kind = 'medical_certificate' AND documentable_type = 'MedicalCertificate')",
                         name: "chk_documents_kind_matches_documentable_type"
    add_check_constraint :documents,
                         "status <> 'signed' OR signed_at IS NOT NULL",
                         name: "chk_documents_signed_requires_signed_at"
    add_check_constraint :documents,
                         "status <> 'cancelled' OR cancelled_at IS NOT NULL",
                         name: "chk_documents_cancelled_requires_cancelled_at"

    add_check_constraint :delivery_logs,
                         "recipient IS NULL OR trim(recipient) <> ''",
                         name: "chk_delivery_logs_recipient_not_blank"
    add_check_constraint :delivery_logs,
                         "status <> 'failed' OR error_message IS NOT NULL",
                         name: "chk_delivery_logs_failed_requires_error_message"
  end
end
