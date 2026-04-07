# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.1].define(version: 2026_04_07_095145) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "audit_logs", force: :cascade do |t|
    t.string "actor_type"
    t.bigint "actor_id"
    t.bigint "patient_id"
    t.bigint "document_id"
    t.string "resource_type", null: false
    t.bigint "resource_id", null: false
    t.string "action", null: false
    t.jsonb "before_data", default: {}, null: false
    t.jsonb "after_data", default: {}, null: false
    t.string "request_id"
    t.string "request_origin"
    t.string "ip_address"
    t.text "user_agent"
    t.datetime "occurred_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_type", "actor_id"], name: "index_audit_logs_on_actor_type_and_actor_id"
    t.index ["document_id"], name: "index_audit_logs_on_document_id"
    t.index ["occurred_at"], name: "index_audit_logs_on_occurred_at"
    t.index ["patient_id"], name: "index_audit_logs_on_patient_id"
    t.index ["request_id"], name: "index_audit_logs_on_request_id"
    t.index ["resource_type", "resource_id"], name: "index_audit_logs_on_resource_type_and_resource_id"
    t.check_constraint "TRIM(BOTH FROM action) <> ''::text", name: "chk_audit_logs_action_not_blank"
    t.check_constraint "action::text = ANY (ARRAY['created'::character varying, 'updated'::character varying, 'signed'::character varying, 'sent'::character varying, 'viewed'::character varying, 'revoked'::character varying, 'status_changed'::character varying]::text[])", name: "chk_audit_logs_action_values"
  end

  create_table "delivery_logs", force: :cascade do |t|
    t.bigint "doctor_id"
    t.bigint "patient_id"
    t.bigint "document_id"
    t.string "channel", null: false
    t.string "status", default: "queued", null: false
    t.integer "attempt_number", default: 1, null: false
    t.string "provider_name"
    t.string "provider_message_id"
    t.string "recipient"
    t.string "error_code"
    t.text "error_message"
    t.datetime "attempted_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.datetime "delivered_at"
    t.string "request_id"
    t.string "idempotency_key"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["attempted_at"], name: "index_delivery_logs_on_attempted_at"
    t.index ["channel", "status", "attempted_at"], name: "idx_delivery_logs_channel_status_attempted_at"
    t.index ["channel"], name: "index_delivery_logs_on_channel"
    t.index ["doctor_id", "patient_id"], name: "index_delivery_logs_on_doctor_id_and_patient_id"
    t.index ["doctor_id", "status"], name: "idx_delivery_logs_on_doctor_id_and_status"
    t.index ["doctor_id"], name: "index_delivery_logs_on_doctor_id"
    t.index ["document_id", "status"], name: "index_delivery_logs_on_document_id_and_status"
    t.index ["document_id"], name: "index_delivery_logs_on_document_id"
    t.index ["idempotency_key"], name: "index_delivery_logs_on_idempotency_key"
    t.index ["patient_id", "status"], name: "idx_delivery_logs_on_patient_id_and_status"
    t.index ["patient_id"], name: "index_delivery_logs_on_patient_id"
    t.index ["request_id"], name: "index_delivery_logs_on_request_id"
    t.index ["status"], name: "index_delivery_logs_on_status"
    t.check_constraint "attempt_number >= 1", name: "chk_delivery_logs_attempt_number_gte_one"
    t.check_constraint "channel::text = ANY (ARRAY['email'::character varying, 'sms'::character varying, 'whatsapp'::character varying]::text[])", name: "chk_delivery_logs_channel_values"
    t.check_constraint "recipient IS NULL OR TRIM(BOTH FROM recipient) <> ''::text", name: "chk_delivery_logs_recipient_not_blank"
    t.check_constraint "status::text <> 'delivered'::text OR delivered_at IS NOT NULL", name: "chk_delivery_logs_delivered_requires_delivered_at"
    t.check_constraint "status::text <> 'failed'::text OR error_message IS NOT NULL", name: "chk_delivery_logs_failed_requires_error_message"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying, 'processing'::character varying, 'sent'::character varying, 'delivered'::character varying, 'failed'::character varying]::text[])", name: "chk_delivery_logs_status_values"
  end

  create_table "doctors", force: :cascade do |t|
    t.string "full_name", null: false
    t.string "email", null: false
    t.string "cpf", null: false
    t.string "license_number", null: false
    t.string "license_state", limit: 2, null: false
    t.string "specialty"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_doctors_on_lower_email", unique: true
    t.index ["active"], name: "index_doctors_on_active"
    t.index ["cpf"], name: "index_doctors_on_cpf", unique: true
    t.index ["license_number", "license_state"], name: "index_doctors_on_license_number_and_license_state", unique: true
    t.check_constraint "TRIM(BOTH FROM email) <> ''::text", name: "chk_doctors_email_not_blank"
    t.check_constraint "char_length(TRIM(BOTH FROM full_name)) >= 3", name: "chk_doctors_full_name_length"
    t.check_constraint "char_length(TRIM(BOTH FROM license_number)) >= 4", name: "chk_doctors_license_number_length"
    t.check_constraint "char_length(cpf::text) >= 11", name: "chk_doctors_cpf_length"
    t.check_constraint "char_length(license_state::text) = 2", name: "chk_doctors_license_state_length"
  end

  create_table "document_versions", force: :cascade do |t|
    t.bigint "document_id", null: false
    t.integer "version_number", null: false
    t.text "content", null: false
    t.string "checksum"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "generated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["document_id", "version_number"], name: "index_document_versions_on_document_id_and_version_number", unique: true
    t.index ["document_id"], name: "index_document_versions_on_document_id"
    t.index ["generated_at"], name: "index_document_versions_on_generated_at"
    t.check_constraint "TRIM(BOTH FROM content) <> ''::text", name: "chk_document_versions_content_not_blank"
    t.check_constraint "version_number >= 1", name: "chk_document_versions_number_gte_one"
  end

  create_table "documents", force: :cascade do |t|
    t.bigint "doctor_id", null: false
    t.bigint "patient_id", null: false
    t.string "documentable_type", null: false
    t.bigint "documentable_id", null: false
    t.string "kind", null: false
    t.string "code", null: false
    t.string "status", default: "issued", null: false
    t.integer "current_version", default: 1, null: false
    t.date "issued_on", null: false
    t.datetime "signed_at"
    t.datetime "cancelled_at"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_documents_on_code", unique: true
    t.index ["doctor_id", "patient_id"], name: "index_documents_on_doctor_id_and_patient_id"
    t.index ["doctor_id", "status"], name: "idx_documents_on_doctor_id_and_status"
    t.index ["doctor_id"], name: "index_documents_on_doctor_id"
    t.index ["documentable_type", "documentable_id"], name: "idx_documents_on_documentable_unique", unique: true
    t.index ["documentable_type", "documentable_id"], name: "index_documents_on_documentable"
    t.index ["kind"], name: "index_documents_on_kind"
    t.index ["patient_id", "status"], name: "idx_documents_on_patient_id_and_status"
    t.index ["patient_id"], name: "index_documents_on_patient_id"
    t.index ["status"], name: "index_documents_on_status"
    t.check_constraint "TRIM(BOTH FROM code) <> ''::text", name: "chk_documents_code_not_blank"
    t.check_constraint "char_length(TRIM(BOTH FROM code)) >= 8", name: "chk_documents_code_length"
    t.check_constraint "current_version >= 1", name: "chk_documents_current_version_gte_one"
    t.check_constraint "kind::text = 'prescription'::text AND documentable_type::text = 'Prescription'::text OR kind::text = 'medical_certificate'::text AND documentable_type::text = 'MedicalCertificate'::text", name: "chk_documents_kind_matches_documentable_type"
    t.check_constraint "kind::text = ANY (ARRAY['prescription'::character varying, 'medical_certificate'::character varying]::text[])", name: "chk_documents_kind_values"
    t.check_constraint "status::text <> 'cancelled'::text OR cancelled_at IS NOT NULL", name: "chk_documents_cancelled_requires_cancelled_at"
    t.check_constraint "status::text <> 'signed'::text OR signed_at IS NOT NULL", name: "chk_documents_signed_requires_signed_at"
    t.check_constraint "status::text = ANY (ARRAY['issued'::character varying, 'sent'::character varying, 'viewed'::character varying, 'revoked'::character varying, 'expired'::character varying]::text[])", name: "chk_documents_status_values"
  end

  create_table "medical_certificates", force: :cascade do |t|
    t.bigint "doctor_id", null: false
    t.bigint "patient_id", null: false
    t.string "code", null: false
    t.text "content", null: false
    t.date "issued_on", null: false
    t.date "rest_start_on", null: false
    t.date "rest_end_on", null: false
    t.string "icd_code"
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_medical_certificates_on_code", unique: true
    t.index ["doctor_id", "patient_id"], name: "index_medical_certificates_on_doctor_id_and_patient_id"
    t.index ["doctor_id", "status"], name: "idx_medical_certificates_on_doctor_id_and_status"
    t.index ["doctor_id"], name: "index_medical_certificates_on_doctor_id"
    t.index ["issued_on"], name: "index_medical_certificates_on_issued_on"
    t.index ["patient_id", "status"], name: "idx_medical_certificates_on_patient_id_and_status"
    t.index ["patient_id"], name: "index_medical_certificates_on_patient_id"
    t.index ["status"], name: "index_medical_certificates_on_status"
    t.check_constraint "TRIM(BOTH FROM code) <> ''::text", name: "chk_medical_certificates_code_not_blank"
    t.check_constraint "TRIM(BOTH FROM content) <> ''::text", name: "chk_medical_certificates_content_not_blank"
    t.check_constraint "char_length(TRIM(BOTH FROM code)) >= 8", name: "chk_medical_certificates_code_length"
    t.check_constraint "rest_end_on >= rest_start_on", name: "chk_medical_certificates_rest_period_order"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'signed'::character varying, 'cancelled'::character varying]::text[])", name: "chk_medical_certificates_status_values"
  end

  create_table "patients", force: :cascade do |t|
    t.string "full_name", null: false
    t.string "cpf", null: false
    t.date "birth_date", null: false
    t.string "email"
    t.string "phone"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index "lower((email)::text)", name: "index_patients_on_lower_email", unique: true, where: "(email IS NOT NULL)"
    t.index ["active"], name: "index_patients_on_active"
    t.index ["cpf"], name: "index_patients_on_cpf", unique: true
    t.check_constraint "char_length(TRIM(BOTH FROM full_name)) >= 3", name: "chk_patients_full_name_length"
    t.check_constraint "char_length(cpf::text) >= 11", name: "chk_patients_cpf_length"
    t.check_constraint "email IS NULL OR TRIM(BOTH FROM email) <> ''::text", name: "chk_patients_email_not_blank"
    t.check_constraint "phone IS NULL OR char_length(regexp_replace(phone::text, '\\D'::text, ''::text, 'g'::text)) >= 10", name: "chk_patients_phone_digits_length"
  end

  create_table "prescriptions", force: :cascade do |t|
    t.bigint "doctor_id", null: false
    t.bigint "patient_id", null: false
    t.string "code", null: false
    t.text "content", null: false
    t.date "issued_on", null: false
    t.date "valid_until"
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_prescriptions_on_code", unique: true
    t.index ["doctor_id", "patient_id"], name: "index_prescriptions_on_doctor_id_and_patient_id"
    t.index ["doctor_id", "status"], name: "idx_prescriptions_on_doctor_id_and_status"
    t.index ["doctor_id"], name: "index_prescriptions_on_doctor_id"
    t.index ["issued_on"], name: "index_prescriptions_on_issued_on"
    t.index ["patient_id", "status"], name: "idx_prescriptions_on_patient_id_and_status"
    t.index ["patient_id"], name: "index_prescriptions_on_patient_id"
    t.index ["status"], name: "index_prescriptions_on_status"
    t.check_constraint "TRIM(BOTH FROM code) <> ''::text", name: "chk_prescriptions_code_not_blank"
    t.check_constraint "TRIM(BOTH FROM content) <> ''::text", name: "chk_prescriptions_content_not_blank"
    t.check_constraint "char_length(TRIM(BOTH FROM code)) >= 8", name: "chk_prescriptions_code_length"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'signed'::character varying, 'cancelled'::character varying]::text[])", name: "chk_prescriptions_status_values"
    t.check_constraint "valid_until IS NULL OR valid_until >= issued_on", name: "chk_prescriptions_valid_until_gte_issued_on"
  end

  add_foreign_key "audit_logs", "documents", on_delete: :nullify
  add_foreign_key "audit_logs", "patients", on_delete: :nullify
  add_foreign_key "delivery_logs", "doctors", on_delete: :nullify
  add_foreign_key "delivery_logs", "documents", on_delete: :nullify
  add_foreign_key "delivery_logs", "patients", on_delete: :nullify
  add_foreign_key "document_versions", "documents", on_delete: :cascade
  add_foreign_key "documents", "doctors", on_delete: :restrict
  add_foreign_key "documents", "patients", on_delete: :restrict
  add_foreign_key "medical_certificates", "doctors", on_delete: :restrict
  add_foreign_key "medical_certificates", "patients", on_delete: :restrict
  add_foreign_key "prescriptions", "doctors", on_delete: :restrict
  add_foreign_key "prescriptions", "patients", on_delete: :restrict
end
