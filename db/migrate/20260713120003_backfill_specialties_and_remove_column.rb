class BackfillSpecialtiesAndRemoveColumn < ActiveRecord::Migration[7.1]
  # Lightweight, decoupled AR classes so the data migration does not depend on
  # the app models (which no longer carry the string column after this runs).
  class MigrationSpecialty < ActiveRecord::Base
    self.table_name = "specialties"
  end

  class MigrationDoctorSpecialty < ActiveRecord::Base
    self.table_name = "doctor_specialties"
  end

  class MigrationDoctorProfile < ActiveRecord::Base
    self.table_name = "doctor_profiles"
  end

  def up
    say_with_time "backfilling doctor specialties from the string column" do
      cache = {}

      MigrationDoctorProfile.where.not(specialty: [nil, ""]).find_each do |profile|
        name = profile.specialty.to_s.strip
        next if name.blank?

        specialty_id = cache[name.downcase] ||= begin
          existing = MigrationSpecialty.where("lower(name) = lower(?)", name).first
          existing ||= MigrationSpecialty.create!(name: name, active: true)
          existing.id
        end

        MigrationDoctorSpecialty.find_or_create_by!(
          doctor_profile_id: profile.id, specialty_id: specialty_id
        )
      end
    end

    remove_column :doctor_profiles, :specialty
  end

  def down
    add_column :doctor_profiles, :specialty, :string

    say_with_time "restoring the string column from the first linked specialty" do
      MigrationDoctorProfile.reset_column_information

      MigrationDoctorProfile.find_each do |profile|
        link = MigrationDoctorSpecialty.where(doctor_profile_id: profile.id).order(:created_at).first
        next if link.nil?

        specialty = MigrationSpecialty.find_by(id: link.specialty_id)
        profile.update_columns(specialty: specialty&.name) if specialty
      end
    end
  end
end
