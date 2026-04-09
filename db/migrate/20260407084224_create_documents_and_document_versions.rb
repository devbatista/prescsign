class CreateDocumentsAndDocumentVersions < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def change
    create_table :documents, id: :uuid do |t|
      t.references :doctor, null: false, foreign_key: true, type: :uuid
      t.references :patient, null: false, foreign_key: true, type: :uuid
      t.references :documentable, polymorphic: true, null: false, type: :uuid
      t.string :kind, null: false
      t.string :code, null: false
      t.string :status, null: false, default: "draft"
      t.integer :current_version, null: false, default: 1
      t.date :issued_on, null: false
      t.datetime :signed_at
      t.datetime :cancelled_at
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :documents, :code, unique: true
    add_index :documents, :kind
    add_index :documents, :status
    add_index :documents, %i[documentable_type documentable_id], unique: true, name: "idx_documents_on_documentable_unique"
    add_index :documents, %i[doctor_id patient_id]

    add_check_constraint :documents,
                         "trim(code) <> ''",
                         name: "chk_documents_code_not_blank"
    add_check_constraint :documents,
                         "char_length(trim(code)) >= 8",
                         name: "chk_documents_code_length"
    add_check_constraint :documents,
                         "kind IN ('prescription', 'medical_certificate')",
                         name: "chk_documents_kind_values"
    add_check_constraint :documents,
                         "status IN ('draft', 'signed', 'cancelled')",
                         name: "chk_documents_status_values"
    add_check_constraint :documents,
                         "current_version >= 1",
                         name: "chk_documents_current_version_gte_one"

    create_table :document_versions, id: :uuid do |t|
      t.references :document, null: false, foreign_key: true, type: :uuid
      t.integer :version_number, null: false
      t.text :content, null: false
      t.string :checksum
      t.jsonb :metadata, null: false, default: {}
      t.datetime :generated_at

      t.timestamps
    end

    add_index :document_versions, %i[document_id version_number], unique: true
    add_index :document_versions, :generated_at

    add_check_constraint :document_versions,
                         "version_number >= 1",
                         name: "chk_document_versions_number_gte_one"
    add_check_constraint :document_versions,
                         "trim(content) <> ''",
                         name: "chk_document_versions_content_not_blank"
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
