require "csv"
require "open-uri"

module Medications
  # Carga do catálogo global de produtos (`Medication`) a partir da Lista de
  # Preços de Medicamentos da CMED/Anvisa — a Fase 2 de
  # docs/sncr/SUBSTANCES_DATA_SOURCING.md §8.
  #
  # A lista da CMED é a fonte pública mais completa por *apresentação*: traz
  # produto, princípio ativo, apresentação, EAN, registro Anvisa, laboratório e
  # tarja. (Os "dados abertos de medicamentos registrados" cobrem mais registros,
  # mas sem EAN, apresentação nem tarja — não servem para o médico escolher a
  # caixa que está prescrevendo.)
  #
  # O CSV **não** é versionado no repo (17 MB, republicado a cada mês): a carga
  # baixa da Anvisa na hora, ou lê um arquivo local via `FILE=`. É idempotente —
  # a chave é o registro Anvisa, com o EAN como chave alternativa para casar
  # cadastro feito à mão no back-office.
  #
  # O que a carga **não** faz, de propósito:
  #   - não reverte `active` de quem já existe (desativação no back-office manda);
  #   - não apaga vínculo produto↔substância criado à mão;
  #   - não classifica por semelhança: princípio ativo que não casa exatamente
  #     fica sem vínculo e sai no relatório de revisão (tmp/…_review.csv).
  class CmedCatalogImport
    class Error < StandardError; end

    SOURCE_URL = "https://dados.anvisa.gov.br/dados/TA_PRECO_MEDICAMENTO_GOV.csv".freeze
    DOWNLOAD_PATH = "tmp/cmed_medicamentos.csv".freeze
    REVIEW_PATH = "tmp/medications_import_review.csv".freeze

    BATCH_SIZE = 1_000

    # O arquivo começa com dezenas de linhas de cabeçalho institucional; a linha
    # de colunas é a primeira cuja primeira célula é "SUBSTÂNCIA".
    HEADER_MARKER = "SUBSTANCIA".freeze

    # Célula "vazia" na CMED vem como travessão, às vezes com nota de rodapé.
    BLANK_CELL = /\A-+\s*(?:\(\*\))?\z/

    # Concentração: a apresentação começa pela dose ("500 MG COM REV CT BL…",
    # "10 MG/G + 0,443 MG/G CREM DERM…"). Sem número + unidade conhecida, não
    # inventa nada — o campo fica nulo para o back-office preencher.
    DOSE_UNIT = /(?:MG|MCG|UG|G|KG|ML|L|UI|U|MEQ|MMOL|%)/
    DOSE = /\d[\d.,]*\s*#{DOSE_UNIT}(?:\s*\/\s*(?:\d[\d.,]*\s*)?#{DOSE_UNIT})?(?![A-ZÇÃÕÁÉÍÓÚÂÊÔ])/
    STRENGTH = /\A#{DOSE}(?:\s*\+\s*#{DOSE})*/

    # Abreviações da CMED -> forma farmacêutica do modelo. A ordem importa:
    # "PO LIOF SOL INJ" é injetável, não solução.
    PHARMACEUTICAL_FORMS = [
      [ /\b(?:SOL INJ|INJ|INFUS|IM\/IV|IV|SC)\b/, "injetavel" ],
      [ /\b(?:COM|COMP|DRG)\b/, "comprimido" ],
      [ /\bCAP\b/, "capsula" ],
      [ /\b(?:XPE|XAR)\b/, "xarope" ],
      [ /\b(?:SUS|SUSP)\b/, "suspensao" ],
      [ /\b(?:GTS|GOT)\b/, "gotas" ],
      [ /\bCREM\b/, "creme" ],
      [ /\bPOM\b/, "pomada" ],
      [ /\bGEL\b/, "gel" ],
      [ /\b(?:AER|SPRAY|SPR)\b/, "spray" ],
      [ /\bADES\b/, "adesivo" ],
      [ /\bSUP\b/, "supositorio" ],
      [ /\bSOL\b/, "solucao" ]
    ].freeze

    Row = Struct.new(
      :name, :active_ingredient, :strength, :pharmaceutical_form, :control_class,
      :anvisa_registration, :ean, :manufacturer, :presentation, :marketed,
      :ingredients, :medication_id, :substance_ids,
      keyword_init: true
    )

    def self.call(path:, io: $stdout, review_path: Rails.root.join(REVIEW_PATH))
      new(path: path, io: io, review_path: review_path).call
    end

    # Baixa a lista publicada pela Anvisa. Fora do `call` para que a importação
    # em si seja testável e reexecutável sem rede.
    #
    # dados.anvisa.gov.br serve só o certificado folha, sem a intermediária: o
    # OpenSSL do Ruby não busca a cadeia faltante (AIA) e recusa a conexão, então
    # o curl entra como plano B — ele busca. Falhando os dois, resta baixar à mão
    # e passar `FILE=`.
    def self.download!(url: SOURCE_URL, to: Rails.root.join(DOWNLOAD_PATH), io: $stdout)
      io.puts "Baixando #{url}"
      to.dirname.mkpath

      begin
        URI.parse(url).open(read_timeout: 300) { |remote| IO.copy_stream(remote, to.to_s) }
      rescue OpenSSL::SSL::SSLError => error
        io.puts "  TLS falhou no Ruby (#{error.message.truncate(80)}); tentando via curl."
        unless system("curl", "-fsSL", "--max-time", "600", "-o", to.to_s, url)
          raise Error, "Não foi possível baixar #{url}. Baixe manualmente e rode com FILE=caminho/do.csv."
        end
      end

      io.puts "  #{(to.size / 1024.0 / 1024).round(1)} MB em #{to}"
      to
    end

    def initialize(path:, io: $stdout, review_path: Rails.root.join(REVIEW_PATH))
      @path = path.to_s
      @io = io
      @review_path = Pathname.new(review_path)
      @created = 0
      @updated = 0
      @unchanged = 0
      @links_created = 0
      @ean_conflicts = 0
      @unmatched = Hash.new(0)
      @unmatched_controlled = Hash.new(0)
      @matches = {}
    end

    def call
      rows = parse
      raise Error, "Nenhuma linha de produto encontrada em #{@path}." if rows.empty?

      resolve_ean_conflicts!(rows)

      ActiveRecord::Base.transaction do
        persist(rows)
        link_substances(rows)
      end

      report(rows)
    end

    private

    # --- leitura -----------------------------------------------------------

    def parse
      rows = []
      seen = Set.new
      columns = nil

      CSV.foreach(@path, col_sep: ";", encoding: "bom|utf-8", liberal_parsing: true) do |csv_row|
        if columns.nil?
          columns = header_map(csv_row) if header?(csv_row)
          next
        end

        row = build_row(csv_row, columns)
        next if row.nil?
        # A lista republica uma linha idêntica de vez em quando.
        next unless seen.add?([ row.anvisa_registration, row.presentation ])

        rows << row
      end

      raise Error, "Cabeçalho da lista CMED não encontrado em #{@path}." if columns.nil?

      @io.puts "Lidas #{rows.size} apresentações de #{@path}."
      rows
    end

    def header?(csv_row)
      normalize_header(csv_row&.first).start_with?(HEADER_MARKER)
    end

    def header_map(csv_row)
      headers = csv_row.map { |cell| normalize_header(cell) }

      columns = {
        ingredient: headers.index(HEADER_MARKER),
        manufacturer: headers.index("LABORATORIO"),
        registration: headers.index("REGISTRO"),
        ean: headers.index("EAN 1"),
        name: headers.index("PRODUTO"),
        presentation: headers.index("APRESENTACAO"),
        control: headers.index("TARJA"),
        marketed: headers.index { |header| header.start_with?("COMERCIALIZACAO") }
      }

      missing = columns.select { |_key, index| index.nil? }.keys
      raise Error, "Colunas ausentes na lista CMED: #{missing.join(', ')}." if missing.any?

      columns
    end

    def build_row(csv_row, columns)
      name = cell(csv_row, columns[:name])
      registration = cell(csv_row, columns[:registration]).to_s.gsub(/\D/, "").presence
      return nil if name.blank? || registration.blank?

      presentation = cell(csv_row, columns[:presentation])
      ingredients = SubstanceMatcher.split_ingredients(cell(csv_row, columns[:ingredient]))

      Row.new(
        name: name,
        active_ingredient: ingredients.join(" + ").presence,
        strength: presentation.to_s[STRENGTH]&.squish,
        pharmaceutical_form: pharmaceutical_form_for(presentation),
        control_class: control_class_for(cell(csv_row, columns[:control])),
        anvisa_registration: registration,
        ean: ean_for(cell(csv_row, columns[:ean])),
        manufacturer: cell(csv_row, columns[:manufacturer]),
        presentation: presentation,
        marketed: cell(csv_row, columns[:marketed]).to_s.casecmp("sim").zero?,
        ingredients: ingredients,
        substance_ids: []
      )
    end

    def cell(csv_row, index)
      value = csv_row[index].to_s.squish
      return nil if value.empty? || value.match?(BLANK_CELL)

      value
    end

    def normalize_header(value)
      value.to_s.unicode_normalize(:nfd).gsub(/\p{Mn}/, "").upcase.squish
    end

    def pharmaceutical_form_for(presentation)
      return nil if presentation.blank?

      text = presentation.upcase
      PHARMACEUTICAL_FORMS.find { |pattern, _form| text.match?(pattern) }&.last
    end

    # Tarja da CMED -> `Medication::CONTROL_CLASSES`. "- (*)" (sem informação)
    # fica nulo: dizer "comum" seria afirmar algo que a fonte não afirma.
    def control_class_for(value)
      text = normalize_header(value)
      return nil if text.blank?
      return "tarja_preta" if text.include?("PRETA")
      return "tarja_vermelha_retencao" if text.include?("VERMELHA") && text.include?("RESTRICAO")
      return "tarja_vermelha" if text.include?("VERMELHA")
      return "comum" if text.include?("SEM TARJA")

      nil
    end

    def ean_for(value)
      digits = value.to_s.gsub(/\D/, "")
      return nil if digits.length < 8 || digits.match?(/\A0+\z/)

      digits
    end

    # O mesmo EAN aparece em registros diferentes (mesma caixa reembalada). O
    # índice único do banco só aceita um: fica com o produto em comercialização.
    def resolve_ean_conflicts!(rows)
      rows.group_by(&:ean).each do |ean, group|
        next if ean.nil? || group.size == 1

        keeper = group.find(&:marketed) || group.first
        (group - [ keeper ]).each do |row|
          row.ean = nil
          @ean_conflicts += 1
        end
      end
    end

    # --- gravação ----------------------------------------------------------

    def persist(rows)
      by_registration = {}
      by_ean = {}
      Medication.find_each do |medication|
        by_registration[medication.anvisa_registration] = medication if medication.anvisa_registration.present?
        by_ean[medication.ean] = medication if medication.ean.present?
      end

      claimed = Set.new
      inserts = []
      now = Time.current

      rows.each do |row|
        existing = by_registration[row.anvisa_registration] || by_ean[row.ean]

        if existing && claimed.add?(existing.id)
          update(existing, row)
          row.medication_id = existing.id
        else
          # O EAN já pertence a outro produto do banco: entra sem ele.
          if existing
            row.ean = nil
            @ean_conflicts += 1
          end

          inserts << attributes_for(row).merge(active: row.marketed, created_at: now, updated_at: now)
        end
      end

      inserts.each_slice(BATCH_SIZE) { |slice| Medication.insert_all!(slice) }
      @created = inserts.size
    end

    def update(medication, row)
      attributes = attributes_for(row)
      # Sem EAN na fonte, mantém o que o back-office já tinha.
      attributes.delete(:ean) if row.ean.blank?
      medication.assign_attributes(attributes)

      if medication.changed?
        medication.save!
        @updated += 1
      else
        @unchanged += 1
      end
    end

    # `active` e `default_posology` ficam de fora: são do back-office.
    def attributes_for(row)
      {
        name: row.name,
        active_ingredient: row.active_ingredient,
        strength: row.strength,
        pharmaceutical_form: row.pharmaceutical_form,
        control_class: row.control_class,
        anvisa_registration: row.anvisa_registration,
        ean: row.ean,
        manufacturer: row.manufacturer,
        presentation: row.presentation
      }
    end

    # --- vínculo com substâncias -------------------------------------------

    def link_substances(rows)
      ids_by_registration = Medication.where.not(anvisa_registration: nil).pluck(:anvisa_registration, :id).to_h
      existing_pairs = MedicationSubstance.pluck(:medication_id, :substance_id).to_set
      pairs = []
      now = Time.current

      rows.each do |row|
        row.medication_id ||= ids_by_registration[row.anvisa_registration]
        next if row.medication_id.nil?

        row.substance_ids = row.ingredients.filter_map { |ingredient| substance_for(ingredient)&.id }.uniq

        if row.substance_ids.empty? && controlled_tarja?(row)
          row.ingredients.each { |ingredient| @unmatched_controlled[ingredient] += 1 }
        end

        row.substance_ids.each do |substance_id|
          next unless existing_pairs.add?([ row.medication_id, substance_id ])

          pairs << { medication_id: row.medication_id, substance_id: substance_id, created_at: now, updated_at: now }
        end
      end

      pairs.each_slice(BATCH_SIZE) { |slice| MedicationSubstance.insert_all!(slice) }
      @links_created = pairs.size
    end

    def substance_for(ingredient)
      @matches[ingredient] = matcher.match(ingredient) unless @matches.key?(ingredient)
      substance = @matches[ingredient]
      @unmatched[ingredient] += 1 if substance.nil?
      substance
    end

    def matcher
      @matcher ||= SubstanceMatcher.new
    end

    def controlled_tarja?(row)
      %w[tarja_preta tarja_vermelha_retencao].include?(row.control_class)
    end

    # --- relatório ---------------------------------------------------------

    def report(rows)
      controlled = rows.count { |row| row.substance_ids.present? }
      review = review_entries

      @io.puts "Medicamentos: #{@created} criados, #{@updated} atualizados, #{@unchanged} sem mudança."
      @io.puts "  Vínculos com substância: #{@links_created} novos; #{controlled} apresentações com substância controlada."
      @io.puts "  EANs em conflito (mantido só no produto comercializado): #{@ean_conflicts}." if @ean_conflicts.positive?
      @io.puts "  Princípios ativos sem casamento: #{@unmatched.size} distintos."

      write_review(review)

      {
        created: @created, updated: @updated, unchanged: @unchanged, total: rows.size,
        links_created: @links_created, controlled: controlled, ean_conflicts: @ean_conflicts,
        unmatched: @unmatched.size, review: review
      }
    end

    # A revisão humana só precisa olhar dois grupos: princípio ativo parecido com
    # uma substância controlada (provável variação de nome que o matcher não
    # desfaz) e produto com tarja preta/retenção que ficou sem nenhum vínculo.
    # O resto do "não casou" é medicamento comum — ruído.
    def review_entries
      @unmatched.filter_map do |ingredient, count|
        near = matcher.near_miss(ingredient)
        controlled = @unmatched_controlled[ingredient]
        next if near.nil? && controlled.zero?

        {
          ingredient: ingredient,
          occurrences: count,
          reason: near ? "quase_casamento" : "tarja_controlada_sem_casamento",
          suggestion: near,
          controlled_presentations: controlled
        }
      end.sort_by { |entry| [ -entry[:controlled_presentations], -entry[:occurrences] ] }
    end

    def write_review(entries)
      return @io.puts("  Nada para revisar." ) if entries.empty?

      @review_path.dirname.mkpath
      CSV.open(@review_path, "w") do |csv|
        csv << %w[principio_ativo ocorrencias motivo substancia_sugerida apresentacoes_com_tarja_controlada]
        entries.each do |entry|
          csv << entry.values_at(:ingredient, :occurrences, :reason, :suggestion, :controlled_presentations)
        end
      end

      @io.puts "  Revisar (#{entries.size} princípios ativos): #{@review_path}"

      near, controlled = entries.partition { |entry| entry[:suggestion].present? }

      if near.any?
        @io.puts "    Parecidos com substância da base (nome que o casamento não desfaz):"
        near.sort_by { |entry| -entry[:occurrences] }.first(10).each do |entry|
          @io.puts "      #{entry[:occurrences].to_s.rjust(4)} apres.  #{entry[:ingredient]} ~ #{entry[:suggestion]}"
        end
      end

      if controlled.any?
        @io.puts "    Tarja preta/retenção sem nenhum vínculo:"
        controlled.first(10).each do |entry|
          @io.puts "      #{entry[:controlled_presentations].to_s.rjust(4)} apres.  #{entry[:ingredient]}"
        end
      end
    end
  end
end
