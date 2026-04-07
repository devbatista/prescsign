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

ActiveRecord::Schema[7.1].define(version: 2026_04_06_214740) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

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
    t.index ["doctor_id"], name: "index_medical_certificates_on_doctor_id"
    t.index ["issued_on"], name: "index_medical_certificates_on_issued_on"
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
    t.index ["doctor_id"], name: "index_prescriptions_on_doctor_id"
    t.index ["issued_on"], name: "index_prescriptions_on_issued_on"
    t.index ["patient_id"], name: "index_prescriptions_on_patient_id"
    t.index ["status"], name: "index_prescriptions_on_status"
    t.check_constraint "TRIM(BOTH FROM code) <> ''::text", name: "chk_prescriptions_code_not_blank"
    t.check_constraint "TRIM(BOTH FROM content) <> ''::text", name: "chk_prescriptions_content_not_blank"
    t.check_constraint "char_length(TRIM(BOTH FROM code)) >= 8", name: "chk_prescriptions_code_length"
    t.check_constraint "status::text = ANY (ARRAY['draft'::character varying, 'signed'::character varying, 'cancelled'::character varying]::text[])", name: "chk_prescriptions_status_values"
    t.check_constraint "valid_until IS NULL OR valid_until >= issued_on", name: "chk_prescriptions_valid_until_gte_issued_on"
  end

  add_foreign_key "medical_certificates", "doctors"
  add_foreign_key "medical_certificates", "patients"
  add_foreign_key "prescriptions", "doctors"
  add_foreign_key "prescriptions", "patients"
end
