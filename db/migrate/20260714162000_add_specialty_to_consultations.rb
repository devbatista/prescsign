class AddSpecialtyToConsultations < ActiveRecord::Migration[7.1]
  def change
    add_reference :consultations, :specialty, type: :uuid, foreign_key: true, index: true
    change_column_null :consultations, :user_id, true

    add_index :consultations, %i[organization_id specialty_id scheduled_at],
              name: "idx_consultations_on_org_specialty_scheduled_at"
  end
end
