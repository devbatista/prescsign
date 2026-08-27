namespace :substances do
  desc "Carrega/atualiza a base de substâncias controladas a partir de db/data/substances.csv (idempotente)"
  task load: :environment do
    load Rails.root.join("db/seeds/14_substances.rb")
    seed_substances!
  end
end
