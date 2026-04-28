class CreateConsultations < ActiveRecord::Migration[7.1]
  def change
    create_table :consultations, id: :uuid do |t|
      t.references :patient, null: false, type: :uuid, foreign_key: { on_delete: :restrict }
      t.references :user, null: false, type: :uuid, foreign_key: { on_delete: :restrict }
      t.references :organization, null: false, type: :uuid, foreign_key: { on_delete: :restrict }
      t.datetime :scheduled_at, null: false
      t.datetime :finished_at
      t.string :status, null: false, default: "scheduled"
      t.text :chief_complaint
      t.text :notes
      t.text :diagnosis
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :consultations,
              %i[organization_id patient_id scheduled_at],
              name: "idx_consultations_on_org_patient_scheduled_at"
    add_index :consultations,
              %i[organization_id status scheduled_at],
              name: "idx_consultations_on_org_status_scheduled_at"
    add_index :consultations,
              %i[user_id scheduled_at],
              name: "idx_consultations_on_user_scheduled_at"

    add_check_constraint :consultations,
                         "status IN ('scheduled', 'completed', 'cancelled')",
                         name: "chk_consultations_status_values"
    add_check_constraint :consultations,
                         "(finished_at IS NULL) OR (finished_at >= scheduled_at)",
                         name: "chk_consultations_finished_at_after_scheduled_at"
  end
end
