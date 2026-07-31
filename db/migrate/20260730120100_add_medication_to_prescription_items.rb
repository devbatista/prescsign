class AddMedicationToPrescriptionItems < ActiveRecord::Migration[7.1]
  def change
    add_reference :prescription_items, :medication, type: :uuid, null: true, index: true
    add_foreign_key :prescription_items, :medications, on_delete: :nullify
  end
end
