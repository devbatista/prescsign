class CreateSpecialties < ActiveRecord::Migration[7.1]
  def change
    create_table :specialties, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :name, null: false
      t.boolean :active, null: false, default: true

      t.timestamps
    end

    add_index :specialties, "lower(name)", unique: true, name: "index_specialties_on_lower_name"
  end
end
