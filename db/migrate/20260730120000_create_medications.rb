class CreateMedications < ActiveRecord::Migration[7.1]
  def change
    create_table :medications, id: :uuid do |t|
      t.string :name, null: false
      t.string :active_ingredient
      t.string :strength
      t.string :pharmaceutical_form
      t.string :control_class
      t.string :anvisa_registration
      t.string :manufacturer
      t.string :ean
      t.string :presentation
      t.text :default_posology
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :medications, :name, name: "index_medications_on_name"
    add_index :medications, :ean,
              unique: true,
              where: "ean IS NOT NULL",
              name: "index_medications_on_ean"

    add_check_constraint :medications,
                         "TRIM(BOTH FROM name) <> ''",
                         name: "chk_medications_name_present"
  end
end
