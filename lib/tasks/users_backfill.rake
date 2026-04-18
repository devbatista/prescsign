require "fileutils"
require "json"

namespace :users do
  namespace :backfill do
    desc "Backfill doctors into users, doctor_profiles and legacy mapping table"
    task from_doctors: :environment do
      report = Users::BackfillFromDoctors.new.call
      serialized = {
        processed_doctors: report.processed_doctors,
        created_users: report.created_users,
        reused_users: report.reused_users,
        created_profiles: report.created_profiles,
        updated_profiles: report.updated_profiles,
        mapped_doctors: report.mapped_doctors,
        updated_organization_responsibles: report.updated_organization_responsibles,
        divergences: report.divergences,
        consistency: report.consistency
      }

      reports_dir = Rails.root.join("tmp", "reports")
      FileUtils.mkdir_p(reports_dir)

      filename = "users_backfill_#{Time.current.utc.strftime("%Y%m%d%H%M%S")}.json"
      path = reports_dir.join(filename)
      File.write(path, JSON.pretty_generate(serialized))

      puts JSON.pretty_generate(serialized)
      puts "Report saved at: #{path}"
      abort("Backfill consistency check failed") unless report.consistency[:consistent]
    end
  end
end
