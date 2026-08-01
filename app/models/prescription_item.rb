# Item estruturado de uma receita (nato digital). Substitui, para receitas
# controladas, o texto livre por dados por medicamento (nome, principio ativo,
# concentracao, quantidade, posologia). Convive com Prescription#content atual.
class PrescriptionItem < ApplicationRecord
  belongs_to :prescription, inverse_of: :prescription_items
  # Vínculo opcional ao catálogo: preenchido quando o item nasce de um Medication
  # (via busca na receita); nulo quando digitado à mão. Os campos abaixo guardam
  # um snapshot, então o item permanece íntegro mesmo se o catálogo mudar/sumir.
  belongs_to :medication, optional: true

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
  before_validation :snapshot_sncr_type_from_medication, on: :create

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

  private

  # Snapshot do tipo SNCR a partir do medicamento do catálogo, no momento da
  # criação. Assim o item mantém a classificação usada na emissão mesmo que a
  # substância/catálogo mude depois. Itens digitados à mão (sem medication) ou já
  # com tipo informado ficam intactos.
  def snapshot_sncr_type_from_medication
    return if sncr_type.present?

    self.sncr_type = medication&.effective_sncr_type
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
