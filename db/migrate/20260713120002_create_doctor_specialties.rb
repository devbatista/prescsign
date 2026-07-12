class CreateDoctorSpecialties < ActiveRecord::Migration[7.1]
  def change
    create_table :doctor_specialties, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :doctor_profile, type: :uuid, null: false, foreign_key: true
      t.references :specialty, type: :uuid, null: false, foreign_key: true
      t.string :rqe_number

      t.timestamps
    end

    add_index :doctor_specialties, %i[doctor_profile_id specialty_id], unique: true,
              name: "index_doctor_specialties_on_profile_and_specialty"
  end
end
