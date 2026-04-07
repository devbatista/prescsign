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

ActiveRecord::Schema[7.1].define(version: 2026_04_06_173000) do
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

end
