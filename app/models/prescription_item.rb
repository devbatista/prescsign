# Item estruturado de uma receita (nato digital). Substitui, para receitas
# controladas, o texto livre por dados por medicamento (nome, principio ativo,
# concentracao, quantidade, posologia). Convive com Prescription#content atual.
class PrescriptionItem < ApplicationRecord
  belongs_to :prescription, inverse_of: :prescription_items
  # Vínculo opcional ao catálogo: preenchido quando o item nasce de um Medication
  # (via busca na receita); nulo quando digitado à mão. Os campos abaixo guardam
  # um snapshot, então o item permanece íntegro mesmo se o catálogo mudar/sumir.
  belongs_to :medication, optional: true
  # Substância que classifica o item quando ele não veio do catálogo: casada
  # automaticamente sobre o texto livre ou identificada pelo médico na busca
  # assistida. É ela, não o médico, quem decide o tipo SNCR.
  belongs_to :substance, optional: true

  validates :name, presence: true
  validates :position,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 },
            uniqueness: { scope: :prescription_id }
  validates :sncr_type, inclusion: { in: Prescription::SNCR_TYPES }, allow_nil: true

  normalizes :name, with: ->(value) { value&.strip }
  normalizes :active_ingredient, with: ->(value) { value&.strip.presence }
  normalizes :strength, with: ->(value) { value&.strip.presence }
  normalizes :quantity, with: ->(value) { value&.strip.presence }
  normalizes :posology, with: ->(value) { value&.strip.presence }
  normalizes :sncr_type, with: ->(value) { value&.strip&.upcase.presence }

  before_validation :assign_position, on: :create
  before_validation :resolve_control_source!
  before_validation :snapshot_sncr_type

  # Resolve de onde sai a classificação deste item: descarta a resposta anterior
  # se o medicamento mudou e tenta casar o texto livre com a base de controladas.
  #
  # É público porque a receita precisa chamá-lo **antes** de derivar o próprio
  # tipo: o `before_validation` do pai roda antes da validação dos filhos, então
  # esperar o callback do item deixaria `Prescription#sync_sncr_type_from_items`
  # olhando para itens ainda não resolvidos. Idempotente — chamar duas vezes no
  # mesmo save não muda o resultado.
  def resolve_control_source!
    discard_resolution_when_source_changes
    match_substance_from_text
    self
  end

  # O item tem de onde derivar sua classificação de controle? Item do catálogo
  # deriva do produto; item de texto livre precisa de uma substância casada ou
  # identificada, ou da afirmação de que nenhuma controlada se aplica. Sem nada
  # disso o sistema não sabe se é controlado — e não pode assumir que não é.
  def control_resolved?
    medication_id.present? || substance_id.present? || uncontrolled_confirmed_at.present?
  end

  # Item digitado à mão, sem vínculo com o catálogo.
  def free_text?
    medication_id.blank?
  end

  # A confirmação chega do formulário como booleano, mas o que se guarda é o
  # instante: a auditoria precisa saber quando a afirmação foi feita, não só que
  # foi. Marcar desfaz qualquer substância identificada antes, porque as duas
  # respostas são mutuamente exclusivas (ver o check constraint da migração).
  def uncontrolled_confirmed=(value)
    if ActiveModel::Type::Boolean.new.cast(value)
      self.substance_id = nil
      self.uncontrolled_confirmed_at ||= Time.current
    else
      self.uncontrolled_confirmed_at = nil
    end
  end

  def uncontrolled_confirmed
    uncontrolled_confirmed_at.present?
  end
  alias_method :uncontrolled_confirmed?, :uncontrolled_confirmed

  # Produto do catálogo cujo nome bate exatamente com o texto digitado. Quando
  # existe, o médico escreveu o nome de um produto que está no catálogo mas não
  # clicou na sugestão — e o caminho certo é selecioná-lo, não classificar à mão.
  def catalog_match_for_typed_name
    return nil unless free_text?
    return nil if name.blank?

    Medication.active.find_by("LOWER(name) = ?", name.to_s.strip.downcase)
  end

  # Linha legível do item, usada para sintetizar Prescription#content e para o
  # PDF. Ex.: "Dipirona 500 mg — 1 caixa — Tomar 1 comprimido de 6/6h".
  def to_content_line
    head = [ name, strength ].compact_blank.join(" ")
    [ head, quantity, posology ].compact_blank.join(" — ")
  end

  # Item exige receituário controlado (herdou um tipo SNCR do catálogo)?
  def controlled?
    sncr_type.present?
  end

  # Genérico do catálogo repete o princípio ativo no próprio nome do produto
  # ("DIPIRONA MONOIDRATADA"). Imprimir as duas linhas iguais na receita só
  # ocupa espaço, então o PDF só mostra o princípio ativo quando ele acrescenta
  # informação.
  def distinct_active_ingredient?
    active_ingredient.present? && !active_ingredient.casecmp?(name.to_s.strip)
  end

  private

  # Snapshot do tipo SNCR na emissão. O catálogo tem precedência sobre a
  # substância avulsa: o produto pode associar mais de uma controlada e já
  # resolve a mais restritiva em `effective_sncr_type`.
  #
  # Só recalcula quando a fonte muda (ou na criação), preservando a intenção
  # original do snapshot — mudança posterior no catálogo ou na base de
  # substâncias não reescreve a classificação de um item já resolvido.
  def snapshot_sncr_type
    return if sncr_type.present?

    self.sncr_type = medication&.effective_sncr_type || substance&.sncr_type
  end

  # Casa o texto livre contra a base de controladas. Cobre o nome genérico
  # ("clonazepam", "amoxicilina") desfazendo sal, hidratação e gênero — o
  # casamento é exato sobre forma normalizada, nunca aproximado, para não
  # classificar receita controlada por semelhança.
  #
  # Não cobre nome comercial: "Rivotril" não casa. Esse caso é tratado por
  # `catalog_match_for_typed_name`, e o que escapa dos dois cai na identificação
  # assistida — ver docs/CLASSIFICACAO_CONTROLADA.md.
  def match_substance_from_text
    return unless free_text?
    return if substance_id.present?

    matched = [ name, active_ingredient ].compact_blank.filter_map { |text| substance_matcher.match(text) }.first
    return if matched.nil?

    # O casamento vence a afirmação do médico, e não o contrário: se o sistema
    # reconhece a substância, não há como declarar que ela não é controlada.
    self.substance = matched
    self.uncontrolled_confirmed_at = nil
  end

  # O médico trocou o que está sendo prescrito: a resposta dada sobre o texto
  # anterior não vale para o novo. Descarta a resolução — inclusive o tipo já
  # gravado — para que o casamento rode de novo e, se não resolver, a pergunta
  # seja refeita.
  def discard_resolution_when_source_changes
    return if new_record?
    return unless name_changed? || active_ingredient_changed? || medication_id_changed?

    self.substance_id = nil
    self.uncontrolled_confirmed_at = nil
    self.sncr_type = nil
  end

  # Compartilhado pela receita: o índice varre as 612 substâncias, e um matcher
  # por item repetiria a varredura a cada linha do mesmo save.
  def substance_matcher
    prescription&.substance_matcher || Medications::SubstanceMatcher.new
  end

  # Ordena por acrescimo dentro da receita quando a posicao nao e informada.
  # Considera irmaos ja carregados (persistidos ou em memoria), permitindo tanto
  # o append incremental quanto a montagem de varios itens antes de salvar.
  def assign_position
    return if position.present?

    siblings = prescription&.prescription_items&.reject { |item| item.equal?(self) } || []
    self.position = (siblings.filter_map(&:position).max || 0) + 1
  end
end
