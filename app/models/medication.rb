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

  # Rótulos das tarjas — fonte única, lida pelo back-office e pelas mensagens da
  # emissão.
  CONTROL_CLASS_LABELS = {
    "comum" => "Comum (sem tarja)",
    "tarja_vermelha" => "Tarja vermelha",
    "tarja_vermelha_retencao" => "Tarja vermelha com retenção",
    "tarja_preta" => "Tarja preta"
  }.freeze

  # Tarjas que, na publicação da CMED, indicam medicamento sujeito a controle
  # especial — as que exigem receituário próprio e numeração SNCR. Tarja vermelha
  # "pura" fica fora de propósito: ela é venda sob prescrição, não controle.
  SNCR_CONTROL_CLASSES = %w[tarja_preta tarja_vermelha_retencao].freeze

  has_many :prescription_items, dependent: :nullify
  has_many :medication_substances, dependent: :destroy
  has_many :substances, through: :medication_substances
  belongs_to :uncontrolled_confirmed_by, class_name: "User", optional: true

  validates :name, presence: true
  validates :pharmaceutical_form, inclusion: { in: PHARMACEUTICAL_FORMS }, allow_blank: true
  validates :control_class, inclusion: { in: CONTROL_CLASSES }, allow_blank: true
  validates :active, inclusion: { in: [ true, false ] }
  validates :ean, uniqueness: { case_sensitive: false }, allow_blank: true
  validates :uncontrolled_confirmed_reason, presence: { message: "é obrigatório ao confirmar que não é controlado" },
                                            if: :uncontrolled_confirmed?

  before_validation :clear_uncontrolled_confirmation_details, unless: :uncontrolled_confirmed?

  normalizes :name, with: ->(value) { value&.strip }
  normalizes :uncontrolled_confirmed_reason, with: ->(value) { value&.strip.presence }
  normalizes :manufacturer, with: ->(value) { value&.strip.presence }
  normalizes :presentation, with: ->(value) { value&.strip.presence }
  normalizes :active_ingredient, with: ->(value) { value&.strip.presence }
  normalizes :strength, with: ->(value) { value&.strip.presence }
  normalizes :anvisa_registration, with: ->(value) { value&.strip.presence }
  normalizes :default_posology, with: ->(value) { value&.strip.presence }
  normalizes :ean, with: ->(value) { value&.gsub(/\D/, "").presence }

  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:name) }
  # Fila de curadoria: produto com tarja de controlado e sem nenhuma substância
  # controlada vinculada (ver #unclassified_controlled?). Sai da fila quem a
  # curadoria confirmou como não controlado — sem isso o ruído da tarja da CMED
  # nunca deixaria a fila zerar.
  scope :unclassified_controlled, -> {
    where(control_class: SNCR_CONTROL_CLASSES)
      .where(uncontrolled_confirmed_at: nil)
      .where.not(
        id: MedicationSubstance.joins(:substance).where.not(substances: { sncr_type: nil }).select(:medication_id)
      )
  }

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

  # Rótulo da tarja publicada ("Tarja preta"); nil quando a fonte não informa.
  def control_class_label
    CONTROL_CLASS_LABELS[control_class]
  end

  # A tarja publicada pela CMED diz que este produto é sujeito a controle especial?
  def control_class_requires_sncr?
    SNCR_CONTROL_CLASSES.include?(control_class)
  end

  # As duas fontes se contradizem: a tarja da CMED diz controlado e nenhuma
  # substância vinculada classifica o produto. Não é caso teórico — é a fila de
  # revisão do casamento CMED↔substância (SUBSTANCES_DATA_SOURCING §8.3).
  #
  # Enquanto a contradição existe o produto **não** pode ser tratado como comum:
  # a tarja é fonte oficial e independente da nossa curadoria, e ignorá-la
  # reproduz, pela porta do catálogo, a mesma falha silenciosa que a
  # classificação do texto livre fechou (ver docs/CLASSIFICACAO_CONTROLADA.md).
  #
  # A contradição só se resolve de dois jeitos, e os dois são decisão humana:
  # vincular a substância que classifica, ou confirmar que a tarja não
  # corresponde a substância controlada (#uncontrolled_confirmed?).
  def unclassified_controlled?
    control_class_requires_sncr? && effective_sncr_type.blank? && !uncontrolled_confirmed?
  end

  # A curadoria confirmou que a tarja de controlado da CMED é ruído — o produto
  # não consta da 344/98 nem da IN 360. Mesmo desenho de
  # PrescriptionItem#uncontrolled_confirmed=: o formulário manda booleano, o que
  # se guarda é o instante. Reconfirmar preserva a data original.
  def uncontrolled_confirmed=(value)
    if ActiveModel::Type::Boolean.new.cast(value)
      self.uncontrolled_confirmed_at ||= Time.current
    else
      self.uncontrolled_confirmed_at = nil
    end
  end

  def uncontrolled_confirmed
    uncontrolled_confirmed_at.present?
  end
  alias_method :uncontrolled_confirmed?, :uncontrolled_confirmed

  private

  # Motivo e autor só fazem sentido junto da confirmação. Limpar aqui, e não no
  # setter, deixa o resultado independente da ordem em que os parâmetros do
  # formulário chegam — e espelha o check constraint da migração.
  def clear_uncontrolled_confirmation_details
    self.uncontrolled_confirmed_reason = nil
    self.uncontrolled_confirmed_by = nil
  end
end
