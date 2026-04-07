class CreateMedicalCertificates < ActiveRecord::Migration[7.1]
  # rubocop:disable Metrics/AbcSize, Metrics/MethodLength
  def change
    create_table :medical_certificates do |t|
      t.references :doctor, null: false, foreign_key: true
      t.references :patient, null: false, foreign_key: true
      t.string :code, null: false
      t.text :content, null: false
      t.date :issued_on, null: false
      t.date :rest_start_on, null: false
      t.date :rest_end_on, null: false
      t.string :icd_code
      t.string :status, null: false, default: "draft"

      t.timestamps
    end

    add_index :medical_certificates, :code, unique: true
    add_index :medical_certificates, :issued_on
    add_index :medical_certificates, :status
    add_index :medical_certificates, %i[doctor_id patient_id]

    add_check_constraint :medical_certificates,
                         "trim(code) <> ''",
                         name: "chk_medical_certificates_code_not_blank"
    add_check_constraint :medical_certificates,
                         "char_length(trim(code)) >= 8",
                         name: "chk_medical_certificates_code_length"
    add_check_constraint :medical_certificates,
                         "trim(content) <> ''",
                         name: "chk_medical_certificates_content_not_blank"
    add_check_constraint :medical_certificates,
                         "status IN ('draft', 'signed', 'cancelled')",
                         name: "chk_medical_certificates_status_values"
    add_check_constraint :medical_certificates,
                         "rest_end_on >= rest_start_on",
                         name: "chk_medical_certificates_rest_period_order"
  end
  # rubocop:enable Metrics/AbcSize, Metrics/MethodLength
end
