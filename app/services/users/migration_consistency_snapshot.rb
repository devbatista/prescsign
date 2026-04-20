module Users
  class MigrationConsistencySnapshot
    class << self
      def call
        missing_mapping_ids = Doctor.where.not(id: LegacyDoctorUserMapping.select(:legacy_doctor_id)).pluck(:id)
        missing_profile_ids = Doctor.where.not(id: DoctorProfile.where.not(doctor_id: nil).select(:doctor_id)).pluck(:id)
        pending_internal_responsible_ids = OrganizationResponsible.where(user_id: nil).where.not(doctor_id: nil).pluck(:id)

        {
          doctors_total: Doctor.count,
          users_total: User.count,
          mappings_total: LegacyDoctorUserMapping.count,
          doctor_profiles_total: DoctorProfile.count,
          organization_responsibles_pending_internal_link_total: pending_internal_responsible_ids.size,
          missing_mapping_doctor_ids: missing_mapping_ids,
          missing_doctor_profile_doctor_ids: missing_profile_ids,
          pending_internal_responsible_ids: pending_internal_responsible_ids,
          consistent: missing_mapping_ids.empty? &&
            missing_profile_ids.empty? &&
            pending_internal_responsible_ids.empty?
        }
      end
    end
  end
end
