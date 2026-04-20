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
    desc "Print consistency snapshot used as cutover readiness gate"
    task readiness: :environment do
      snapshot = Users::MigrationConsistencySnapshot.call

      puts JSON.pretty_generate(snapshot)
      abort("Users migration readiness check failed") unless snapshot[:consistent]
    end
  end
end
