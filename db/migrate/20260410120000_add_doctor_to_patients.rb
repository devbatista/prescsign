class AddDoctorToPatients < ActiveRecord::Migration[7.1]
  def change
    add_reference :patients, :doctor, type: :uuid, null: false, foreign_key: { on_delete: :restrict }
    add_index :patients, %i[doctor_id full_name], name: "idx_patients_on_doctor_id_and_full_name"
    add_index :patients, %i[doctor_id cpf], unique: true, name: "idx_patients_on_doctor_id_and_cpf_unique"
  end
end
