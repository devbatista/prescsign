class CreatePrescriptionItems < ActiveRecord::Migration[7.1]
  def change
    create_table :prescription_items, id: :uuid do |t|
      t.uuid :prescription_id, null: false
      t.integer :position, null: false
      t.string :name, null: false
      t.string :active_ingredient
      t.string :strength
      t.string :quantity
      t.text :posology

      t.timestamps
    end

    add_index :prescription_items, :prescription_id,
              name: "index_prescription_items_on_prescription_id"
    add_index :prescription_items, [ :prescription_id, :position ],
              unique: true,
              name: "index_prescription_items_on_prescription_id_and_position"

    add_foreign_key :prescription_items, :prescriptions, on_delete: :cascade

    add_check_constraint :prescription_items,
                         "TRIM(BOTH FROM name) <> ''",
                         name: "chk_prescription_items_name_not_blank"
    add_check_constraint :prescription_items,
                         "position >= 1",
                         name: "chk_prescription_items_position_gte_one"
  end
end
