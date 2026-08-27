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
  puts "Catalogo: #{Medication.count} medicamentos (recorte de demonstracao) e #{Substance.count} substancias."
  puts "  Catalogo completo da CMED: bin/rails medications:import (o seed trunca a tabela)."
  puts "Receitas controladas de exemplo: RX-SEED-0007 (RCE, rascunho) e RX-SEED-0008 (NRB, assinada)."
  puts "  Mais numeracao simulada: rake 'sncr:seed_pool[medico@prescsign.test,NRB]' com SNCR_FAKE=true."
end
