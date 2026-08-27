namespace :sncr do
  desc "Popula o pool de numerações simuladas de um médico (exige SNCR_FAKE=true). Ex.: rake 'sncr:seed_pool[medico@exemplo.com,NRB]'"
  task :seed_pool, %i[email sncr_type] => :environment do |_task, args|
    unless Sncr::ClientFactory.fake?
      abort "sncr:seed_pool só roda em modo simulado. Defina SNCR_FAKE=true (indisponível em produção)."
    end

    email = args[:email].to_s.strip.downcase
    sncr_type = args[:sncr_type].to_s.strip.upcase

    user = User.find_by(email: email)
    abort "Usuário não encontrado: #{email}" if user.nil?

    doctor_profile = user.doctor_profile
    abort "Usuário #{email} não tem perfil de médico." if doctor_profile.nil?

    unless Prescription::SNCR_TYPES.include?(sncr_type)
      abort "Tipo inválido: #{sncr_type}. Use um de #{Prescription::SNCR_TYPES.join(', ')}."
    end

    imported = Sncr::NumberingBatch.request!(doctor_profile: doctor_profile, sncr_type: sncr_type)
    balance = SncrNumbering.balance_for(doctor_profile)

    puts "#{imported} numeração(ões) simuladas de #{sncr_type} importadas para #{email}."
    puts "Saldo do pool: #{balance.map { |type, count| "#{type}=#{count}" }.join(', ')}"
  rescue Sncr::Error => e
    abort "Falha ao gerar numeração: #{e.message}"
  end
end
