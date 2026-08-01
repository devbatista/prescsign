# Catálogo global de medicamentos da plataforma (gerido no back-office). É a
# fonte de referência que o médico consulta ao emitir uma receita — cada
# PrescriptionItem pode nascer a partir de um Medication (snapshot + vínculo
# opcional). Não é multi-tenant: a lista é única para toda a plataforma.
class Medication < ApplicationRecord
  # Forma farmacêutica (apresentação física do medicamento).
  PHARMACEUTICAL_FORMS = %w[
    comprimido capsula solucao suspensao xarope pomada creme gel gotas
    injetavel spray adesivo supositorio outro
  ].freeze

  # Classe de controle / tarja regulatória (Portaria 344/98 e afins).
  CONTROL_CLASSES = %w[comum tarja_vermelha tarja_vermelha_retencao tarja_preta].freeze

  has_many :prescription_items, dependent: :nullify
  has_many :medication_substances, dependent: :destroy
  has_many :substances, through: :medication_substances

  validates :name, presence: true
  validates :pharmaceutical_form, inclusion: { in: PHARMACEUTICAL_FORMS }, allow_blank: true
  validates :control_class, inclusion: { in: CONTROL_CLASSES }, allow_blank: true
  validates :active, inclusion: { in: [ true, false ] }
  validates :ean, uniqueness: { case_sensitive: false }, allow_blank: true

  normalizes :name, with: ->(value) { value&.strip }
  normalizes :manufacturer, with: ->(value) { value&.strip.presence }
  normalizes :presentation, with: ->(value) { value&.strip.presence }
  normalizes :active_ingredient, with: ->(value) { value&.strip.presence }
  normalizes :strength, with: ->(value) { value&.strip.presence }
  normalizes :anvisa_registration, with: ->(value) { value&.strip.presence }
  normalizes :default_posology, with: ->(value) { value&.strip.presence }
  normalizes :ean, with: ->(value) { value&.gsub(/\D/, "").presence }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }

  # Rótulo curto para exibição (ex.: "Dipirona 500 mg").
  def label
    [ name, strength ].compact_blank.join(" ")
  end

  # Tipo SNCR efetivo do produto: o mais restritivo entre as substâncias
  # controladas ligadas a ele. nil quando nenhuma exige SNCR (medicamento comum).
  # A precedência (Prescription::SNCR_TYPE_PRECEDENCE) resolve o caso raro de um
  # produto associar substâncias de tipos diferentes.
  def effective_sncr_type
    Prescription.most_restrictive_sncr_type(substances.filter_map(&:sncr_type))
  end
end
