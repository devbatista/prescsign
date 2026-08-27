# frozen_string_literal: true

Dir[Rails.root.join("db/seeds/[0-9][0-9]_*.rb")].sort.each { |seed_file| load seed_file }

ActiveRecord::Base.transaction do
  reset_seed_data!

  context = {}
  context[:specialties_by_name] = seed_specialties!
  seed_substances!
  context.merge!(seed_organizations!)
  context.merge!(seed_users!(context))
  context.merge!(seed_doctor_profiles!(context))
  context.merge!(seed_patients!(context))
  context.merge!(seed_consultations!(context))
  context.merge!(seed_clinical_documents!(context))
  context.merge!(seed_document_records!(context))
  seed_delivery_logs!(context)
  seed_invitations!(context)
  seed_audit_logs!(context)
end

print_seed_summary!
