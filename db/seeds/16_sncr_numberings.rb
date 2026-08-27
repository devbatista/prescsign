# frozen_string_literal: true

# Pool de numeração SNCR do prescritor de demonstração (Dra. Ana), para que a
# assinatura de receita controlada funcione logo depois do seed: sem número
# disponível, Documents::SigningService aborta com SncrNumbering::PoolEmpty.
#
# Os números são simulados — vêm do Sncr::FakeClient, o mesmo que atende o modo
# SNCR_FAKE, com o prefixo 9xxx que marca numeração de teste (ver §8.1 de
# docs/sncr/SNCR_INTEGRATION.md). Por isso o seed **só popula em development**:
# número inventado em receita controlada de verdade seria falsificação de
# documento sanitário. Rodar em qualquer outro ambiente simplesmente não semeia.
#
# A solicitação passa por Sncr::NumberingBatch, e não pelo cliente direto, para
# seguir as mesmas regras da API real: NRB/NRR saem como lista de 50 números;
# RCE/RET como bloco contínuo de 1.000 e exigem o CNPJ da plataforma
# (SNCR_PLATFORM_CNPJ) — sem ele a Anvisa recusaria, e aqui o tipo é pulado com
# aviso, em vez de fingir que deu certo.
SEED_SNCR_TYPES = %w[NRB NRR RCE RET].freeze

def seed_sncr_numberings!(context, io: $stdout)
  unless Rails.env.development?
    io.puts "Numeração SNCR: pool simulado não semeado (só em development)."
    return
  end

  doctor_profile = context.fetch(:ana_profile)
  signed_controlled_prescription = context.fetch(:signed_controlled_prescription)

  SEED_SNCR_TYPES.each do |sncr_type|
    next if SncrNumbering.for_doctor(doctor_profile).of_type(sncr_type).exists?

    Sncr::NumberingBatch.request!(
      doctor_profile: doctor_profile,
      sncr_type: sncr_type,
      client: Sncr::FakeClient.new
    )
  rescue Sncr::Error => error
    io.puts "  #{sncr_type}: não semeado (#{error.message})"
  end

  # A receita controlada já assinada gasta um número do pool, como a assinatura
  # faria — assim o painel de numerações abre com histórico de consumo, não só
  # com saldo.
  if signed_controlled_prescription.controlled? && signed_controlled_prescription.sncr_numbering.nil?
    SncrNumbering.consume_next!(
      doctor_profile: doctor_profile,
      sncr_type: signed_controlled_prescription.sncr_type,
      prescription: signed_controlled_prescription
    )
  end

  balance = SncrNumbering.balance_for(doctor_profile)
  io.puts "Numeração SNCR simulada de #{doctor_profile.full_name}: " \
          "#{balance.map { |type, count| "#{type}=#{count}" }.join(', ').presence || 'pool vazio'}."
rescue SncrNumbering::PoolEmpty => error
  io.puts "Numeração SNCR: #{error.message}"
end
