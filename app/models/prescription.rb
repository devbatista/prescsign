class Prescription < ApplicationRecord
  STATUSES = %w[draft signed cancelled].freeze
  # Tipos de receita controlada exigidos pelo SNCR (Anvisa). Quando presente, a
  # receita segue o fluxo controlado (numeracao SNCR + assinatura qualificada);
  # quando ausente (nil), e uma receita comum.
  SNCR_TYPES = %w[NRA NRB NRB2 NRR NRT RCE RET].freeze

  # Precedência de restrição entre os tipos SNCR (mais restritivo primeiro). Serve
  # para resolver o tipo efetivo quando um único medicamento associa mais de uma
  # substância controlada de tipos distintos. Ordem preliminar — o peso
  # regulatório exato precisa ser confirmado (ver docs/sncr/SNCR_INTEGRATION.md).
  SNCR_TYPE_PRECEDENCE = %w[NRA NRT NRB2 NRB NRR RCE RET].freeze

  # Rótulos legíveis de cada tipo (fonte única, usada no formulário de emissão e
  # na área de numerações do painel).
  SNCR_TYPE_LABELS = {
    "NRA" => "Notificação de Receita A (entorpecentes)",
    "NRB" => "Notificação de Receita B (psicotrópicos)",
    "NRB2" => "Notificação de Receita B2 (retinoides sistêmicos)",
    "NRR" => "Notificação Especial (retinoides)",
    "NRT" => "Notificação de Talidomida",
    "RCE" => "Receita de Controle Especial (C1/C5)",
    "RET" => "Receita Sujeita a Retenção (antimicrobianos, GLP-1)"
  }.freeze

  # Cor do badge no receituário, seguindo as cores históricas das notificações
  # (Portaria 344/98): NRA amarela, NRB/NRB2 azul; os demais eram brancos, então
  # ficam neutros. É convenção visual — no modelo eletrônico a cor não tem o
  # mesmo peso regulatório do talão físico.
  SNCR_TYPE_BADGE_COLORS = {
    "NRA" => "yellow",
    "NRB" => "blue",
    "NRB2" => "blue",
    "NRR" => "neutral",
    "NRT" => "neutral",
    "RCE" => "neutral",
    "RET" => "neutral"
  }.freeze

  belongs_to :user
  belongs_to :patient
  belongs_to :organization
  has_one :document, as: :documentable, dependent: :restrict_with_exception
  has_one :sncr_numbering, dependent: :restrict_with_exception
  has_many :prescription_items, -> { order(:position) },
           inverse_of: :prescription, dependent: :destroy

  accepts_nested_attributes_for :prescription_items, allow_destroy: true,
    reject_if: ->(attrs) { attrs[:name].blank? }

  scope :controlled, -> { where.not(sncr_type: nil) }
  scope :common, -> { where(sncr_type: nil) }

  validates :code, presence: true, uniqueness: true, length: { minimum: 8 }
  validates :content, presence: true
  validates :issued_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :sncr_type, inclusion: { in: SNCR_TYPES }, allow_nil: true
  validates :valid_until, comparison: { greater_than_or_equal_to: :issued_on }, allow_nil: true

  normalizes :code, with: ->(value) { value&.strip&.upcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }
  normalizes :sncr_type, with: ->(value) { value&.strip&.upcase.presence }

  before_validation :assign_default_organization
  before_validation :assign_default_user
  before_validation :sync_content_from_items
  before_validation :sync_sncr_type_from_items

  validate :organization_must_match_relations
  validate :controlled_items_must_share_type

  # Dado um conjunto de tipos SNCR, devolve o mais restritivo segundo
  # SNCR_TYPE_PRECEDENCE (nil se vazio). Usado por Medication#effective_sncr_type
  # e pela derivação da receita.
  def self.most_restrictive_sncr_type(types)
    types.compact.min_by { |type| SNCR_TYPE_PRECEDENCE.index(type) || Float::INFINITY }
  end

  # Receita controlada segue o fluxo SNCR (numeracao Anvisa + assinatura
  # qualificada). Ausencia de sncr_type = receita comum.
  def controlled?
    sncr_type.present?
  end

  # Variante de cor do badge SNCR no PDF ("yellow" | "blue" | "neutral").
  def sncr_badge_color
    SNCR_TYPE_BADGE_COLORS.fetch(sncr_type, "neutral")
  end

  # Itens estruturados ativos (ignora os marcados para remoção no formulário
  # aninhado), ordenados por posição. Base para o content sintetizado e o PDF.
  def active_prescription_items
    prescription_items.reject(&:marked_for_destruction?)
                      .sort_by { |item| item.position || Float::INFINITY }
  end

  # Há prescrição estruturada (itens) em vez de só texto livre?
  def structured?
    active_prescription_items.any?
  end

  # Tipos SNCR resolvidos dos itens estruturados: o snapshot já gravado no item ou,
  # enquanto ele ainda não foi persistido (mesmo ciclo de save), o tipo derivado do
  # medicamento do catálogo. Vazio para receita em texto livre / itens comuns.
  def resolved_item_sncr_types
    active_prescription_items.filter_map do |item|
      item.sncr_type.presence || item.medication&.effective_sncr_type
    end.uniq
  end

  private

  # Deriva o sncr_type da receita a partir dos itens do catálogo — a substância é a
  # fonte de verdade, não a escolha manual. Só age quando os itens apontam para um
  # único tipo controlado; receita em texto livre (sem itens classificados)
  # preserva o tipo escolhido à mão. Tipos divergentes são barrados por
  # controlled_items_must_share_type.
  def sync_sncr_type_from_items
    types = resolved_item_sncr_types
    return unless types.size == 1

    self.sncr_type = types.first
  end

  # Um receituário controlado só comporta um tipo (endpoint/modelo Anvisa próprio).
  # Se os itens resolverem para tipos diferentes, a emissão é barrada e o médico é
  # orientado a separar em receitas distintas.
  def controlled_items_must_share_type
    types = resolved_item_sncr_types
    return if types.size <= 1

    errors.add(:base,
      "A receita tem medicamentos de tipos de controle diferentes (#{types.join(', ')}). " \
      "Cada tipo exige um receituário próprio — emita receitas separadas.")
  end

  # Mantém Prescription#content como fonte de verdade do documento/PDF/checksum:
  # quando há itens estruturados, o texto é derivado deles no save. Receitas em
  # texto livre (sem itens) preservam o content digitado.
  def sync_content_from_items
    items = active_prescription_items
    return if items.empty?

    self.content = items.each_with_index.map do |item, index|
      "#{index + 1}. #{item.to_content_line}"
    end.join("\n")
  end

  def assign_default_organization
    self.organization_id ||= patient&.organization_id || user&.current_organization_id
  end

  def assign_default_user
    self.user_id ||= patient&.user_id || Current.user&.id
  end

  def organization_must_match_relations
    return if organization_id.nil?
    return if patient.nil? || user.nil?
    return if patient.organization_id == organization_id && user.membership_for(organization_id).present?

    errors.add(:organization_id, "must match patient and user organization context")
  end
end
