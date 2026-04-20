require "json"

namespace :qa do
  desc "Run critical regression suite for users migration rollout"
  task users_migration_regression: :environment do
    spec_files = %w[
      spec/requests/authentication_spec.rb
      spec/requests/document_emission_spec.rb
      spec/requests/document_signature_spec.rb
      spec/requests/document_resend_spec.rb
      spec/requests/audit_logs_spec.rb
      spec/requests/organizations_spec.rb
    ]

    command = ["bundle", "exec", "rspec", *spec_files]
    success = system(*command)
    abort("Critical users migration regression suite failed") unless success
  end
end

namespace :users do
  namespace :migration do
    desc "Users-only readiness gate"
    task readiness: :environment do
      doctor_user_ids = User.joins(:user_roles)
                            .where(user_roles: { role: "doctor", status: "active" })
                            .distinct
                            .pluck(:id)
      profiled_user_ids = DoctorProfile.where(user_id: doctor_user_ids).pluck(:user_id)
      missing_profile_user_ids = doctor_user_ids - profiled_user_ids

      snapshot = {
        users_total: User.count,
        doctor_profiles_total: DoctorProfile.count,
        doctor_users_total: doctor_user_ids.size,
        missing_profile_user_ids: missing_profile_user_ids,
        consistent: missing_profile_user_ids.empty?
      }

      puts JSON.pretty_generate(snapshot)
      abort("Users migration readiness check failed") unless snapshot[:consistent]
    end
  end
end
