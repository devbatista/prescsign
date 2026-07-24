# Item estruturado de uma receita (nato digital). Substitui, para receitas
# controladas, o texto livre por dados por medicamento (nome, principio ativo,
# concentracao, quantidade, posologia). Convive com Prescription#content atual.
class PrescriptionItem < ApplicationRecord
  belongs_to :prescription, inverse_of: :prescription_items

  validates :name, presence: true
  validates :position,
            presence: true,
            numericality: { only_integer: true, greater_than_or_equal_to: 1 },
            uniqueness: { scope: :prescription_id }

  normalizes :name, with: ->(value) { value&.strip }
  normalizes :active_ingredient, with: ->(value) { value&.strip.presence }
  normalizes :strength, with: ->(value) { value&.strip.presence }
  normalizes :quantity, with: ->(value) { value&.strip.presence }

  before_validation :assign_position, on: :create

  private

  # Ordena por acrescimo dentro da receita quando a posicao nao e informada.
  # Considera irmaos ja carregados (persistidos ou em memoria), permitindo tanto
  # o append incremental quanto a montagem de varios itens antes de salvar.
  def assign_position
    return if position.present?

    siblings = prescription&.prescription_items&.reject { |item| item.equal?(self) } || []
    self.position = (siblings.filter_map(&:position).max || 0) + 1
  end
end
