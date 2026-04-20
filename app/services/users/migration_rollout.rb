module Users
  class MigrationRollout
    USERS_REQUIRED_PHASES = %w[
      phase3_users_required
      phase4_cutover_final
      phase_final_users_only
    ].freeze

    class << self
      def phase
        Rails.application.config.x.users_migration.phase.to_s
      end

      def users_required?
        Rails.application.config.x.auth.users_required || USERS_REQUIRED_PHASES.include?(phase)
      end

      def doctor_fallback_allowed?
        Rails.application.config.x.auth.users_fallback_provisioning &&
          Rails.application.config.x.users_migration.allow_doctor_fallback &&
          !users_required?
      end
    end
  end
end
