class DefineDocumentLifecycleStatuses < ActiveRecord::Migration[7.1]
  OLD_STATUSES = %w[draft signed cancelled].freeze
  NEW_STATUSES = %w[issued sent viewed revoked expired].freeze

  def up
    execute <<~SQL
      UPDATE documents
      SET status = CASE status
        WHEN 'draft' THEN 'issued'
        WHEN 'signed' THEN 'sent'
        WHEN 'cancelled' THEN 'revoked'
        ELSE status
      END
    SQL

    remove_check_constraint :documents, name: "chk_documents_status_values", if_exists: true
    add_check_constraint :documents,
                         "status IN ('issued', 'sent', 'viewed', 'revoked', 'expired')",
                         name: "chk_documents_status_values"

    change_column_default :documents, :status, from: "draft", to: "issued"
  end

  def down
    execute <<~SQL
      UPDATE documents
      SET status = CASE status
        WHEN 'issued' THEN 'draft'
        WHEN 'sent' THEN 'signed'
        WHEN 'revoked' THEN 'cancelled'
        WHEN 'viewed' THEN 'signed'
        WHEN 'expired' THEN 'cancelled'
        ELSE status
      END
    SQL

    remove_check_constraint :documents, name: "chk_documents_status_values", if_exists: true
    add_check_constraint :documents,
                         "status IN ('draft', 'signed', 'cancelled')",
                         name: "chk_documents_status_values"

    change_column_default :documents, :status, from: "issued", to: "draft"
  end
end
