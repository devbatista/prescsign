# frozen_string_literal: true

require "csv"

# Base de substâncias controladas e sua classificação SNCR. É a fonte de verdade
# regulatória de que trata docs/sncr/SUBSTANCES_DATA_SOURCING.md: o produto
# (Medication) aponta para substâncias e o tipo de receituário é derivado delas.
#
# A carga lê db/data/substances.csv (dado curado, versionado junto do código) e
# faz upsert por nome — case-insensitive, como o índice único da tabela. É
# idempotente: rodar de novo não duplica nem reverte edições de `active`.
#
# Fontes do CSV (extraídas e conferidas em 25/08/2026):
#
#   - Anexo I da Portaria SVS/MS nº 344/1998, no texto consolidado vigente
#     publicado pela RDC nº 1.036/2026 (Atualização nº 101). Listas carregadas e
#     o tipo SNCR que o próprio subtítulo oficial de cada lista determina:
#       A1, A2, A3 "Notificação de Receita A"          -> NRA
#       B1         "Notificação de Receita B"          -> NRB
#       B2         "Notificação de Receita B2"         -> NRB2
#       C1, C5     "Receita de Controle Especial"      -> RCE
#       C2         "Notificação de Receita Especial"   -> NRR  (retinoicas)
#       C3         "Notificação de Receita Especial"   -> NRT  (imunossupressoras)
#
#   - Instrução Normativa nº 360/2025, que define a lista da RDC nº 471/2021:
#     art. 1º (antimicrobianos) e art. 2º (agonistas de GLP-1), ambos -> RET.
#
# Ficam de fora as listas D1, D2, E e F1-F4: precursores, insumos químicos,
# plantas proscritas e substâncias de uso proscrito não geram receituário
# controlado, então não têm tipo SNCR acionável. A lista C4 não existe mais no
# Anexo I vigente.
SUBSTANCES_CSV_PATH = Rails.root.join("db/data/substances.csv")

# Carrega o CSV curado. Retorna um resumo com o que foi criado/atualizado e as
# substâncias que existem no banco mas não constam do CSV — quando uma RDC exclui
# uma substância, elas aparecem aqui para revisão humana em vez de serem
# desativadas automaticamente (desativar sozinho apagaria cadastro manual do
# back-office; deixar controlada a mais erra para o lado seguro).
def seed_substances!(path: SUBSTANCES_CSV_PATH, io: $stdout)
  rows = CSV.read(path, headers: true)
  created = 0
  updated = 0
  names = []

  rows.each do |row|
    name = row["name"].to_s.strip
    next if name.empty?

    names << name
    substance = Substance.where("lower(name) = ?", name.downcase).first || Substance.new
    substance.assign_attributes(
      name: name,
      list_344: row["list_344"].to_s.strip.presence,
      sncr_type: row["sncr_type"].to_s.strip.presence,
      active: true
    )

    if substance.new_record?
      created += 1
    elsif substance.changed?
      updated += 1
    end

    substance.save!
  end

  orphans =
    if names.any?
      Substance.where("lower(name) NOT IN (?)", names.map(&:downcase)).pluck(:name)
    else
      Substance.pluck(:name)
    end

  io.puts "Substâncias: #{created} criadas, #{updated} atualizadas, #{rows.size} no CSV."
  io.puts "  Fora do CSV (revisar à mão): #{orphans.join(', ')}" if orphans.any?

  { created: created, updated: updated, total: rows.size, orphans: orphans }
end
