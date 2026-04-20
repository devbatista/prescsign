module Auth
  class UserIdentityResolver
    class << self
      def resolve_for_doctor(doctor, allow_provisioning: fallback_provisioning_enabled?)
        return nil if doctor.blank?

        mapped_user = user_from_mapping(doctor)
        return mapped_user if mapped_user.present?

        user = user_by_email(doctor.email)
        return link_existing_user!(doctor, user) if user.present?

        return nil unless allow_provisioning

        provision_user_for_doctor!(doctor)
      end

      def fallback_provisioning_enabled?
        Rails.application.config.x.auth.users_fallback_provisioning &&
          Rails.application.config.x.users_migration.allow_doctor_fallback
      end

      private

      def user_from_mapping(doctor)
        doctor.legacy_doctor_user_mapping&.user || doctor.doctor_profile&.user
      end

      def user_by_email(email)
        normalized = email.to_s.strip.downcase
        return nil if normalized.blank?

        User.where("LOWER(email) = ?", normalized).first
      end

      def link_existing_user!(doctor, user)
        ActiveRecord::Base.transaction do
          sync_confirmation!(user, doctor)
          ensure_doctor_role!(user)
          ensure_doctor_profile!(doctor, user)
          ensure_legacy_mapping!(doctor, user)
        end
        user
      end

      def provision_user_for_doctor!(doctor)
        user = nil
        ActiveRecord::Base.transaction do
          user = User.create!(
            email: doctor.email,
            encrypted_password: doctor.encrypted_password.presence || "",
            status: doctor.active? ? "active" : "inactive"
          )
          sync_confirmation!(user, doctor)
          ensure_doctor_role!(user)
          ensure_doctor_profile!(doctor, user)
          ensure_legacy_mapping!(doctor, user)
        end
        user
      end

      def ensure_doctor_role!(user)
        role = user.user_roles.find_or_initialize_by(role: "doctor")
        role.status = "active"
        role.save! if role.new_record? || role.changed?
      end

      def ensure_doctor_profile!(doctor, user)
        profile = DoctorProfile.find_or_initialize_by(user_id: user.id)
        profile.doctor_id = doctor.id
        profile.cpf = doctor.cpf
        profile.license_number = doctor.license_number
        profile.license_state = doctor.license_state
        profile.specialty = doctor.specialty
        profile.save!
      end

      def ensure_legacy_mapping!(doctor, user)
        mapping = LegacyDoctorUserMapping.find_or_initialize_by(legacy_doctor_id: doctor.id)
        mapping.user_id = user.id
        mapping.backfilled_at = Time.current
        mapping.save!
      end

      def sync_confirmation!(user, doctor)
        return unless doctor.respond_to?(:confirmed_at)
        return if doctor.confirmed_at.blank?
        return if user.confirmed_at.present?

        user.update!(
          confirmed_at: doctor.confirmed_at,
          confirmation_sent_at: doctor.confirmation_sent_at || doctor.confirmed_at
        )
      end
    end
  end
end
