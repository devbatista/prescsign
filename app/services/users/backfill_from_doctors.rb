module Users
  class BackfillFromDoctors
    Report = Struct.new(
      :processed_doctors,
      :created_users,
      :reused_users,
      :created_profiles,
      :updated_profiles,
      :mapped_doctors,
      :updated_organization_responsibles,
      :divergences,
      :consistency,
      keyword_init: true
    )

    def call
      report = Report.new(
        processed_doctors: 0,
        created_users: 0,
        reused_users: 0,
        created_profiles: 0,
        updated_profiles: 0,
        mapped_doctors: 0,
        updated_organization_responsibles: 0,
        divergences: [],
        consistency: {}
      )

      Doctor.find_each do |doctor|
        report.processed_doctors += 1
        backfill_doctor!(doctor, report)
      rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
        report.divergences << divergence_for(doctor, e.message)
      end

      report.updated_organization_responsibles = backfill_organization_responsibles!
      report.consistency = consistency_snapshot
      report
    end

    private

    def backfill_doctor!(doctor, report)
      user, user_created = find_or_create_user_for!(doctor)
      report.created_users += 1 if user_created
      report.reused_users += 1 unless user_created

      ensure_doctor_role!(user)
      created_profile = upsert_doctor_profile!(doctor, user)
      report.created_profiles += 1 if created_profile
      report.updated_profiles += 1 unless created_profile

      upsert_mapping!(doctor, user)
      report.mapped_doctors += 1
    end

    def find_or_create_user_for!(doctor)
      normalized_email = doctor.email.to_s.strip.downcase
      user = User.where("LOWER(email) = ?", normalized_email).first
      return [ user, false ] if user

      user = User.create!(
        email: normalized_email,
        encrypted_password: doctor.encrypted_password.presence || "",
        status: doctor.active? ? "active" : "inactive"
      )
      [ user, true ]
    end

    def ensure_doctor_role!(user)
      role = user.user_roles.find_or_initialize_by(role: "doctor")
      role.status = "active"
      role.save! if role.new_record? || role.changed?
    end

    def upsert_doctor_profile!(doctor, user)
      profile = DoctorProfile.find_or_initialize_by(user: user)
      created = profile.new_record?

      profile.doctor = doctor
      profile.cpf = doctor.cpf
      profile.license_number = doctor.license_number
      profile.license_state = doctor.license_state
      profile.specialty = doctor.specialty
      profile.save!

      created
    end

    def upsert_mapping!(doctor, user)
      mapping = LegacyDoctorUserMapping.find_or_initialize_by(legacy_doctor: doctor)
      mapping.user = user
      mapping.backfilled_at = Time.current
      mapping.save!
    end

    def backfill_organization_responsibles!
      updated_count = 0

      OrganizationResponsible.where(user_id: nil).where.not(doctor_id: nil).find_each do |responsible|
        mapping = LegacyDoctorUserMapping.find_by(legacy_doctor_id: responsible.doctor_id)
        next unless mapping

        updated_count += 1 if responsible.update(user_id: mapping.user_id)
      end

      updated_count
    end

    def consistency_snapshot
      Users::MigrationConsistencySnapshot.call
    end

    def divergence_for(doctor, message)
      {
        legacy_doctor_id: doctor.id,
        doctor_email: doctor.email,
        error: message
      }
    end
  end
end
