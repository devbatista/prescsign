# Substância ativa e sua classificação de controle (Portaria 344/98 e afins). É a
# fonte de verdade regulatória que decide se um medicamento exige SNCR: o produto
# (Medication) aponta para uma ou mais substâncias (N:N) e o tipo SNCR da receita
# é derivado delas — em vez de o médico escolher à mão.
#
# `list_344` guarda a lista da 344/98 apenas como referência/auditoria; `sncr_type`
# é o campo acionável (nil = substância não controlada). A decisão foi guardar o
# tipo SNCR direto na substância porque o mapeamento lista→tipo tem exceções.
class Substance < ApplicationRecord
  has_many :medication_substances, dependent: :destroy
  has_many :medications, through: :medication_substances

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :sncr_type, inclusion: { in: Prescription::SNCR_TYPES }, allow_nil: true
  validates :active, inclusion: { in: [ true, false ] }

  normalizes :name, with: ->(value) { value&.strip }
  normalizes :list_344, with: ->(value) { value&.strip.presence }
  normalizes :sncr_type, with: ->(value) { value&.strip&.upcase.presence }

  scope :controlled, -> { where.not(sncr_type: nil) }
  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }

  # Substância exige receituário controlado (numeração SNCR)?
  def controlled?
    sncr_type.present?
  end

  # Rótulo curto para exibição: "clonazepam (NRB)".
  def label
    controlled? ? "#{name} (#{sncr_type})" : name
  end
end
