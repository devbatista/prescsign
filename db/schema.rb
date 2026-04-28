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

ActiveRecord::Schema[7.1].define(version: 2026_04_28_110000) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pgcrypto"
  enable_extension "plpgsql"

  create_table "active_storage_attachments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.uuid "record_id", null: false
    t.uuid "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "audit_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "actor_type"
    t.uuid "actor_id"
    t.uuid "patient_id"
    t.uuid "document_id"
    t.string "resource_type", null: false
    t.uuid "resource_id", null: false
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
    t.uuid "organization_id"
    t.uuid "unit_id"
    t.uuid "user_id"
    t.index ["action"], name: "index_audit_logs_on_action"
    t.index ["actor_type", "actor_id"], name: "index_audit_logs_on_actor_type_and_actor_id"
    t.index ["document_id"], name: "index_audit_logs_on_document_id"
    t.index ["occurred_at"], name: "index_audit_logs_on_occurred_at"
    t.index ["organization_id", "actor_type", "actor_id", "occurred_at"], name: "idx_audit_logs_on_organization_actor_occurred_at"
    t.index ["organization_id", "document_id", "occurred_at"], name: "idx_audit_logs_on_organization_document_occurred_at"
    t.index ["organization_id", "occurred_at"], name: "idx_audit_logs_on_organization_id_and_occurred_at"
    t.index ["organization_id", "patient_id", "occurred_at"], name: "idx_audit_logs_on_organization_patient_occurred_at"
    t.index ["organization_id", "unit_id"], name: "idx_audit_logs_on_organization_id_and_unit_id"
    t.index ["organization_id", "user_id", "occurred_at"], name: "idx_audit_logs_on_organization_user_occurred_at"
    t.index ["organization_id"], name: "index_audit_logs_on_organization_id"
    t.index ["patient_id"], name: "index_audit_logs_on_patient_id"
    t.index ["request_id"], name: "index_audit_logs_on_request_id"
    t.index ["resource_type", "resource_id"], name: "index_audit_logs_on_resource_type_and_resource_id"
    t.index ["unit_id"], name: "index_audit_logs_on_unit_id"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
    t.check_constraint "TRIM(BOTH FROM action) <> ''::text", name: "chk_audit_logs_action_not_blank"
    t.check_constraint "action::text = ANY (ARRAY['created'::character varying, 'updated'::character varying, 'signed'::character varying, 'sent'::character varying, 'viewed'::character varying, 'revoked'::character varying, 'status_changed'::character varying]::text[])", name: "chk_audit_logs_action_values"
  end

  create_table "auth_refresh_tokens", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "revoked_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["expires_at"], name: "index_auth_refresh_tokens_on_expires_at"
    t.index ["revoked_at"], name: "index_auth_refresh_tokens_on_revoked_at"
    t.index ["token_digest"], name: "index_auth_refresh_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_auth_refresh_tokens_on_user_id"
    t.check_constraint "TRIM(BOTH FROM token_digest) <> ''::text", name: "chk_auth_refresh_tokens_token_digest_not_blank"
  end

  create_table "consultations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "patient_id", null: false
    t.uuid "user_id", null: false
    t.uuid "organization_id", null: false
    t.datetime "scheduled_at", null: false
    t.datetime "finished_at"
    t.string "status", default: "scheduled", null: false
    t.text "chief_complaint"
    t.text "notes"
    t.text "diagnosis"
    t.jsonb "metadata", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "patient_id", "scheduled_at"], name: "idx_consultations_on_org_patient_scheduled_at"
    t.index ["organization_id", "status", "scheduled_at"], name: "idx_consultations_on_org_status_scheduled_at"
    t.index ["organization_id"], name: "index_consultations_on_organization_id"
    t.index ["patient_id"], name: "index_consultations_on_patient_id"
    t.index ["user_id", "scheduled_at"], name: "idx_consultations_on_user_scheduled_at"
    t.index ["user_id"], name: "index_consultations_on_user_id"
    t.check_constraint "finished_at IS NULL OR finished_at >= scheduled_at", name: "chk_consultations_finished_at_after_scheduled_at"
    t.check_constraint "status::text = ANY (ARRAY['scheduled'::character varying, 'completed'::character varying, 'cancelled'::character varying]::text[])", name: "chk_consultations_status_values"
  end

  create_table "delivery_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "patient_id"
    t.uuid "document_id"
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
    t.uuid "organization_id"
    t.uuid "user_id"
    t.index ["attempted_at"], name: "index_delivery_logs_on_attempted_at"
    t.index ["channel", "status", "attempted_at"], name: "idx_delivery_logs_channel_status_attempted_at"
    t.index ["channel"], name: "index_delivery_logs_on_channel"
    t.index ["document_id", "status"], name: "index_delivery_logs_on_document_id_and_status"
    t.index ["document_id"], name: "index_delivery_logs_on_document_id"
    t.index ["idempotency_key"], name: "idx_delivery_logs_on_idempotency_key_unique", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["organization_id", "status"], name: "idx_delivery_logs_on_organization_id_and_status"
    t.index ["organization_id", "user_id"], name: "idx_delivery_logs_on_organization_id_and_user_id"
    t.index ["organization_id"], name: "index_delivery_logs_on_organization_id"
    t.index ["patient_id", "status"], name: "idx_delivery_logs_on_patient_id_and_status"
    t.index ["patient_id"], name: "index_delivery_logs_on_patient_id"
    t.index ["request_id"], name: "index_delivery_logs_on_request_id"
    t.index ["status"], name: "index_delivery_logs_on_status"
    t.index ["user_id"], name: "index_delivery_logs_on_user_id"
    t.check_constraint "attempt_number >= 1", name: "chk_delivery_logs_attempt_number_gte_one"
    t.check_constraint "channel::text = ANY (ARRAY['email'::character varying, 'sms'::character varying, 'whatsapp'::character varying]::text[])", name: "chk_delivery_logs_channel_values"
    t.check_constraint "recipient IS NULL OR TRIM(BOTH FROM recipient) <> ''::text", name: "chk_delivery_logs_recipient_not_blank"
    t.check_constraint "status::text <> 'delivered'::text OR delivered_at IS NOT NULL", name: "chk_delivery_logs_delivered_requires_delivered_at"
    t.check_constraint "status::text <> 'failed'::text OR error_message IS NOT NULL", name: "chk_delivery_logs_failed_requires_error_message"
    t.check_constraint "status::text = ANY (ARRAY['queued'::character varying, 'processing'::character varying, 'sent'::character varying, 'delivered'::character varying, 'failed'::character varying]::text[])", name: "chk_delivery_logs_status_values"
  end

  create_table "doctor_profiles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "cpf"
    t.string "license_number", null: false
    t.string "license_state", limit: 2, null: false
    t.string "specialty"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "full_name"
    t.string "email"
    t.boolean "active", default: true, null: false
    t.string "gender"
    t.index "lower((email)::text)", name: "idx_doctor_profiles_on_lower_email_unique", unique: true
    t.index ["cpf"], name: "index_doctor_profiles_on_cpf", unique: true, where: "(cpf IS NOT NULL)"
    t.index ["license_number", "license_state"], name: "idx_doctor_profiles_on_license_unique", unique: true
    t.index ["user_id"], name: "index_doctor_profiles_on_user_id", unique: true
    t.check_constraint "TRIM(BOTH FROM license_number) <> ''::text", name: "chk_doctor_profiles_license_number_not_blank"
    t.check_constraint "char_length(license_state::text) = 2", name: "chk_doctor_profiles_license_state_length"
    t.check_constraint "cpf IS NULL OR char_length(cpf::text) >= 11", name: "chk_doctor_profiles_cpf_length"
    t.check_constraint "gender IS NULL OR (gender::text = ANY (ARRAY['male'::character varying, 'female'::character varying]::text[]))", name: "chk_doctor_profiles_gender_values"
  end

  create_table "document_versions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "document_id", null: false
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

  create_table "documents", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "patient_id", null: false
    t.string "documentable_type", null: false
    t.uuid "documentable_id", null: false
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
    t.uuid "organization_id", null: false
    t.uuid "unit_id", null: false
    t.uuid "user_id", null: false
    t.index ["code"], name: "index_documents_on_code", unique: true
    t.index ["documentable_type", "documentable_id"], name: "idx_documents_on_documentable_unique", unique: true
    t.index ["documentable_type", "documentable_id"], name: "index_documents_on_documentable"
    t.index ["kind"], name: "index_documents_on_kind"
    t.index ["organization_id", "status"], name: "idx_documents_on_organization_id_and_status"
    t.index ["organization_id", "unit_id"], name: "idx_documents_on_organization_id_and_unit_id"
    t.index ["organization_id", "user_id"], name: "idx_documents_on_organization_id_and_user_id"
    t.index ["organization_id"], name: "index_documents_on_organization_id"
    t.index ["patient_id", "status"], name: "idx_documents_on_patient_id_and_status"
    t.index ["patient_id"], name: "index_documents_on_patient_id"
    t.index ["status"], name: "index_documents_on_status"
    t.index ["unit_id"], name: "index_documents_on_unit_id"
    t.index ["user_id"], name: "index_documents_on_user_id"
    t.check_constraint "TRIM(BOTH FROM code) <> ''::text", name: "chk_documents_code_not_blank"
    t.check_constraint "char_length(TRIM(BOTH FROM code)) >= 8", name: "chk_documents_code_length"
    t.check_constraint "current_version >= 1", name: "chk_documents_current_version_gte_one"
    t.check_constraint "kind::text = 'prescription'::text AND documentable_type::text = 'Prescription'::text OR kind::text = 'medical_certificate'::text AND documentable_type::text = 'MedicalCertificate'::text", name: "chk_documents_kind_matches_documentable_type"
    t.check_constraint "kind::text = ANY (ARRAY['prescription'::character varying, 'medical_certificate'::character varying]::text[])", name: "chk_documents_kind_values"
    t.check_constraint "status::text <> 'cancelled'::text OR cancelled_at IS NOT NULL", name: "chk_documents_cancelled_requires_cancelled_at"
    t.check_constraint "status::text <> 'signed'::text OR signed_at IS NOT NULL", name: "chk_documents_signed_requires_signed_at"
    t.check_constraint "status::text = ANY (ARRAY['issued'::character varying, 'sent'::character varying, 'viewed'::character varying, 'revoked'::character varying, 'expired'::character varying]::text[])", name: "chk_documents_status_values"
  end

  create_table "idempotency_keys", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.string "scope", null: false
    t.string "key", null: false
    t.string "request_fingerprint", null: false
    t.integer "status_code"
    t.jsonb "response_body", default: {}, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["created_at"], name: "index_idempotency_keys_on_created_at"
    t.index ["organization_id"], name: "index_idempotency_keys_on_organization_id"
    t.index ["user_id", "organization_id", "scope", "key"], name: "idx_idempotency_keys_user_uniqueness", unique: true
    t.index ["user_id"], name: "index_idempotency_keys_on_user_id"
  end

  create_table "jwt_denylists", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "jti", null: false
    t.datetime "exp", null: false
    t.index ["exp"], name: "index_jwt_denylists_on_exp"
    t.index ["jti"], name: "index_jwt_denylists_on_jti", unique: true
  end

  create_table "medical_certificates", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "patient_id", null: false
    t.string "code", null: false
    t.text "content", null: false
    t.date "issued_on", null: false
    t.date "rest_start_on", null: false
    t.date "rest_end_on", null: false
    t.string "icd_code"
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "organization_id", null: false
    t.uuid "user_id", null: false
    t.index ["code"], name: "index_medical_certificates_on_code", unique: true
    t.index ["issued_on"], name: "index_medical_certificates_on_issued_on"
    t.index ["organization_id", "status"], name: "idx_medical_certificates_on_organization_id_and_status"
    t.index ["organization_id", "user_id"], name: "idx_medical_certificates_on_organization_id_and_user_id"
    t.index ["organization_id"], name: "index_medical_certificates_on_organization_id"
    t.index ["patient_id", "status"], name: "idx_medical_certificates_on_patient_id_and_status"
    t.index ["patient_id"], name: "index_medical_certificates_on_patient_id"
    t.index ["status"], name: "index_medical_certificates_on_status"
    t.index ["user_id"], name: "index_medical_certificates_on_user_id"
    t.check_constraint "TRIM(BOTH FROM code) <> ''::text", name: "chk_medical_certificates_code_not_blank"
    t.check_constraint "TRIM(BOTH FROM content) <> ''::text", name: "chk_medical_certificates_content_not_blank"
    t.check_constraint "char_length(TRIM(BOTH FROM code)) >= 8", name: "chk_medical_certificates_code_length"
    t.check_constraint "rest_end_on >= rest_start_on", name: "chk_medical_certificates_rest_period_order"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'signed'::character varying, 'cancelled'::character varying]::text[])", name: "chk_medical_certificates_status_values"
  end

  create_table "organization_memberships", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.string "role", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id", null: false
    t.index ["organization_id", "role"], name: "idx_org_memberships_org_role"
    t.index ["organization_id"], name: "index_organization_memberships_on_organization_id"
    t.index ["user_id", "organization_id"], name: "idx_org_memberships_unique_user_org", unique: true
    t.index ["user_id", "status"], name: "idx_org_memberships_user_status"
    t.index ["user_id"], name: "index_organization_memberships_on_user_id"
    t.check_constraint "role::text = ANY (ARRAY['owner'::character varying, 'admin'::character varying, 'doctor'::character varying, 'staff'::character varying]::text[])", name: "chk_organization_memberships_role_values"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying]::text[])", name: "chk_organization_memberships_status_values"
  end

  create_table "organization_registration_invitations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.uuid "invited_by_user_id"
    t.string "invited_email", null: false
    t.string "token_digest", null: false
    t.datetime "expires_at", null: false
    t.datetime "accepted_at"
    t.uuid "accepted_by_user_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["accepted_at"], name: "idx_org_registration_invitations_on_accepted_at"
    t.index ["organization_id", "invited_email"], name: "idx_org_registration_invitations_on_org_and_email"
    t.index ["token_digest"], name: "idx_org_registration_invitations_on_token_digest_unique", unique: true
  end

  create_table "organization_responsibles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "user_id"
    t.index ["organization_id", "created_at"], name: "idx_org_responsibles_on_org_id_and_created_at"
    t.index ["organization_id", "user_id"], name: "idx_org_responsibles_on_org_id_and_user_id"
    t.index ["organization_id"], name: "index_organization_responsibles_on_organization_id"
    t.index ["user_id"], name: "index_organization_responsibles_on_user_id"
  end

  create_table "organizations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "kind", null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "legal_name"
    t.string "trade_name"
    t.string "cnpj"
    t.string "email"
    t.string "phone"
    t.string "zip_code"
    t.string "street"
    t.string "number"
    t.string "complement"
    t.string "district"
    t.string "city"
    t.string "state", limit: 2
    t.string "country", limit: 2
    t.jsonb "metadata", default: {}, null: false
    t.index ["active"], name: "index_organizations_on_active"
    t.index ["cnpj"], name: "index_organizations_on_cnpj", unique: true, where: "(cnpj IS NOT NULL)"
    t.index ["kind"], name: "index_organizations_on_kind"
    t.check_constraint "TRIM(BOTH FROM name) <> ''::text", name: "chk_organizations_name_not_blank"
    t.check_constraint "cnpj IS NULL OR TRIM(BOTH FROM cnpj) <> ''::text AND char_length(cnpj::text) = 14", name: "chk_organizations_cnpj_length"
    t.check_constraint "kind::text = 'autonomo'::text OR cnpj IS NOT NULL", name: "chk_organizations_cnpj_required_for_legal_entity"
    t.check_constraint "kind::text = 'autonomo'::text OR legal_name IS NOT NULL", name: "chk_organizations_legal_name_required_for_legal_entity"
    t.check_constraint "kind::text = ANY (ARRAY['autonomo'::character varying, 'clinica'::character varying, 'hospital'::character varying]::text[])", name: "chk_organizations_kind_values"
  end

  create_table "patients", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "full_name", null: false
    t.string "cpf", null: false
    t.date "birth_date", null: false
    t.string "email"
    t.string "phone"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "organization_id", null: false
    t.uuid "user_id", null: false
    t.index "organization_id, lower((email)::text)", name: "idx_patients_on_organization_id_and_lower_email_unique", unique: true, where: "(email IS NOT NULL)"
    t.index ["active"], name: "index_patients_on_active"
    t.index ["organization_id", "cpf"], name: "idx_patients_on_organization_id_and_cpf_unique", unique: true
    t.index ["organization_id", "full_name"], name: "idx_patients_on_organization_id_and_full_name"
    t.index ["organization_id", "user_id"], name: "idx_patients_on_organization_id_and_user_id"
    t.index ["organization_id"], name: "index_patients_on_organization_id"
    t.index ["user_id"], name: "index_patients_on_user_id"
    t.check_constraint "char_length(TRIM(BOTH FROM full_name)) >= 3", name: "chk_patients_full_name_length"
    t.check_constraint "char_length(cpf::text) >= 11", name: "chk_patients_cpf_length"
    t.check_constraint "email IS NULL OR TRIM(BOTH FROM email) <> ''::text", name: "chk_patients_email_not_blank"
    t.check_constraint "phone IS NULL OR char_length(regexp_replace(phone::text, '\\D'::text, ''::text, 'g'::text)) >= 10", name: "chk_patients_phone_digits_length"
  end

  create_table "prescriptions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "patient_id", null: false
    t.string "code", null: false
    t.text "content", null: false
    t.date "issued_on", null: false
    t.date "valid_until"
    t.string "status", default: "draft", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "organization_id", null: false
    t.uuid "user_id", null: false
    t.index ["code"], name: "index_prescriptions_on_code", unique: true
    t.index ["issued_on"], name: "index_prescriptions_on_issued_on"
    t.index ["organization_id", "status"], name: "idx_prescriptions_on_organization_id_and_status"
    t.index ["organization_id", "user_id"], name: "idx_prescriptions_on_organization_id_and_user_id"
    t.index ["organization_id"], name: "index_prescriptions_on_organization_id"
    t.index ["patient_id", "status"], name: "idx_prescriptions_on_patient_id_and_status"
    t.index ["patient_id"], name: "index_prescriptions_on_patient_id"
    t.index ["status"], name: "index_prescriptions_on_status"
    t.index ["user_id"], name: "index_prescriptions_on_user_id"
    t.check_constraint "TRIM(BOTH FROM code) <> ''::text", name: "chk_prescriptions_code_not_blank"
    t.check_constraint "TRIM(BOTH FROM content) <> ''::text", name: "chk_prescriptions_content_not_blank"
    t.check_constraint "char_length(TRIM(BOTH FROM code)) >= 8", name: "chk_prescriptions_code_length"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'signed'::character varying, 'cancelled'::character varying]::text[])", name: "chk_prescriptions_status_values"
    t.check_constraint "valid_until IS NULL OR valid_until >= issued_on", name: "chk_prescriptions_valid_until_gte_issued_on"
  end

  create_table "units", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "organization_id", null: false
    t.string "name", null: false
    t.string "code"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["organization_id", "active"], name: "idx_units_on_organization_id_and_active"
    t.index ["organization_id", "name"], name: "idx_units_on_organization_id_and_name", unique: true
    t.index ["organization_id"], name: "index_units_on_organization_id"
    t.check_constraint "TRIM(BOTH FROM name) <> ''::text", name: "chk_units_name_not_blank"
  end

  create_table "user_roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.string "role", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["role", "status"], name: "idx_user_roles_on_role_and_status"
    t.index ["user_id", "role"], name: "idx_user_roles_on_user_id_and_role_unique", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
    t.check_constraint "role::text = ANY (ARRAY['doctor'::character varying, 'admin'::character varying, 'support'::character varying, 'manager'::character varying, 'super_admin'::character varying]::text[])", name: "chk_user_roles_role_values"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying]::text[])", name: "chk_user_roles_status_values"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "status", default: "active", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.string "confirmation_token"
    t.datetime "confirmed_at"
    t.datetime "confirmation_sent_at"
    t.string "unconfirmed_email"
    t.uuid "current_organization_id"
    t.index "lower((email)::text)", name: "index_users_on_lower_email", unique: true
    t.index ["confirmation_token"], name: "index_users_on_confirmation_token", unique: true
    t.index ["current_organization_id"], name: "index_users_on_current_organization_id"
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
    t.index ["status"], name: "index_users_on_status"
    t.check_constraint "TRIM(BOTH FROM email) <> ''::text", name: "chk_users_email_not_blank"
    t.check_constraint "status::text = ANY (ARRAY['active'::character varying, 'inactive'::character varying, 'blocked'::character varying]::text[])", name: "chk_users_status_values"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "audit_logs", "documents", on_delete: :nullify
  add_foreign_key "audit_logs", "organizations", on_delete: :nullify
  add_foreign_key "audit_logs", "patients", on_delete: :nullify
  add_foreign_key "audit_logs", "units", on_delete: :nullify
  add_foreign_key "audit_logs", "users", on_delete: :nullify
  add_foreign_key "auth_refresh_tokens", "users", on_delete: :nullify
  add_foreign_key "consultations", "organizations", on_delete: :restrict
  add_foreign_key "consultations", "patients", on_delete: :restrict
  add_foreign_key "consultations", "users", on_delete: :restrict
  add_foreign_key "delivery_logs", "documents", on_delete: :nullify
  add_foreign_key "delivery_logs", "organizations", on_delete: :nullify
  add_foreign_key "delivery_logs", "patients", on_delete: :nullify
  add_foreign_key "delivery_logs", "users", on_delete: :nullify
  add_foreign_key "doctor_profiles", "users", on_delete: :cascade
  add_foreign_key "document_versions", "documents", on_delete: :cascade
  add_foreign_key "documents", "organizations", on_delete: :restrict
  add_foreign_key "documents", "patients", on_delete: :restrict
  add_foreign_key "documents", "units", on_delete: :restrict
  add_foreign_key "documents", "users", on_delete: :restrict
  add_foreign_key "idempotency_keys", "organizations", on_delete: :cascade
  add_foreign_key "idempotency_keys", "users", on_delete: :cascade
  add_foreign_key "medical_certificates", "organizations", on_delete: :restrict
  add_foreign_key "medical_certificates", "patients", on_delete: :restrict
  add_foreign_key "medical_certificates", "users", on_delete: :restrict
  add_foreign_key "organization_memberships", "organizations", on_delete: :restrict
  add_foreign_key "organization_memberships", "users", on_delete: :restrict
  add_foreign_key "organization_registration_invitations", "organizations", on_delete: :cascade
  add_foreign_key "organization_registration_invitations", "users", column: "accepted_by_user_id", on_delete: :nullify
  add_foreign_key "organization_registration_invitations", "users", column: "invited_by_user_id", on_delete: :nullify
  add_foreign_key "organization_responsibles", "organizations", on_delete: :restrict
  add_foreign_key "organization_responsibles", "users", on_delete: :nullify
  add_foreign_key "patients", "organizations", on_delete: :restrict
  add_foreign_key "patients", "users", on_delete: :restrict
  add_foreign_key "prescriptions", "organizations", on_delete: :restrict
  add_foreign_key "prescriptions", "patients", on_delete: :restrict
  add_foreign_key "prescriptions", "users", on_delete: :restrict
  add_foreign_key "units", "organizations", on_delete: :restrict
  add_foreign_key "user_roles", "users", on_delete: :cascade
  add_foreign_key "users", "organizations", column: "current_organization_id", on_delete: :nullify
end
