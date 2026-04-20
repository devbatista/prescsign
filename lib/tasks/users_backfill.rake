namespace :users do
  namespace :backfill do
    desc "No-op: doctor backfill removed after users-only cutover"
    task from_doctors: :environment do
      puts "users:backfill:from_doctors skipped (doctor model removed; users-only identity is active)"
    end
  end
end
