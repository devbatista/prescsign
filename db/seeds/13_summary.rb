# frozen_string_literal: true

def print_seed_summary!
  puts "Seed complete."
  puts "Demo users:"
  puts "  admin@prescsign.test / #{SEED_PASSWORD} (admin)"
  puts "  support@prescsign.test / #{SEED_PASSWORD} (support)"
  puts "  medico@prescsign.test / #{SEED_PASSWORD} (medico em duas clinicas)"
  puts "  recepcao@prescsign.test / #{SEED_PASSWORD} (responsavel pela clinica)"
  puts "  hospital@prescsign.test / #{SEED_PASSWORD} (responsavel pelo hospital)"
  puts "  hospital.medico@prescsign.test / #{SEED_PASSWORD} (medico do hospital)"
  puts "  dermato@prescsign.test / #{SEED_PASSWORD} (medica dermatologista)"
  puts "  pediatra@prescsign.test / #{SEED_PASSWORD} (medico pediatra)"
  puts "  ortopedista@prescsign.test / #{SEED_PASSWORD} (medico ortopedista)"
  puts "  gineco@prescsign.test / #{SEED_PASSWORD} (medica ginecologista)"
  puts "  psiquiatra@prescsign.test / #{SEED_PASSWORD} (medica psiquiatra)"
end
