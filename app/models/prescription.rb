class Prescription < ApplicationRecord
  STATUSES = %w[draft signed cancelled].freeze
  # Tipos de receita controlada exigidos pelo SNCR (Anvisa). Quando presente, a
  # receita segue o fluxo controlado (numeracao SNCR + assinatura qualificada);
  # quando ausente (nil), e uma receita comum.
  SNCR_TYPES = %w[NRA NRB NRB2 NRR NRT RCE RET].freeze

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

  belongs_to :user
  belongs_to :patient
  belongs_to :organization
  has_one :document, as: :documentable, dependent: :restrict_with_exception
  has_one :sncr_numbering, dependent: :restrict_with_exception
  has_many :prescription_items, -> { order(:position) },
           inverse_of: :prescription, dependent: :destroy

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

  validate :organization_must_match_relations

  # Receita controlada segue o fluxo SNCR (numeracao Anvisa + assinatura
  # qualificada). Ausencia de sncr_type = receita comum.
  def controlled?
    sncr_type.present?
  end

  private

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
