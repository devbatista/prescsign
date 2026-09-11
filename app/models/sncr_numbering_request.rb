# Uma linha por *solicitacao* de numeracao ao SNCR — nao por numero. E o que
# torna a cota da Anvisa contavel e auditavel.
#
# Derivar a cota de sncr_numberings.obtained_at seria mais barato e estaria
# errado: aquilo conta numeros, e o limite de RCE/RET e de requisicoes. Pior,
# some justamente quando a cota foi gasta sem numero entrar — resposta vazia,
# rollback da importacao, ou timeout depois de a Anvisa ja ter processado.
#
# Ciclo de vida: `pending` nasce e commita ANTES da chamada HTTP (ver
# Sncr::NumberingBatch), e vira `succeeded`, `failed` ou `unknown` depois.
class SncrNumberingRequest < ApplicationRecord
  ENDPOINTS = %w[notificacao especial_retencao].freeze
  STATUSES = %w[pending succeeded failed unknown].freeze
  ORIGINS = %w[manual on_demand auto_refill].freeze

  # Pendente que ficou para tras (processo morto entre a reserva e o desfecho).
  # Passado esse prazo ele conta como `unknown` para efeito de cota: a Anvisa
  # pode ter processado, e num limite irreversivel o palpite seguro e o que
  # bloqueia.
  PENDING_GRACE = 15.minutes

  belongs_to :doctor_profile
  belongs_to :user, optional: true
  has_many :sncr_numberings, dependent: :nullify

  validates :sncr_type, inclusion: { in: Prescription::SNCR_TYPES }
  validates :endpoint, inclusion: { in: ENDPOINTS }
  validates :status, inclusion: { in: STATUSES }
  validates :origin, inclusion: { in: ORIGINS }
  validates :requested_quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :council, :license_number, :license_state, presence: true
  validates :requested_at, presence: true
  validate :lifecycle_consistency

  scope :for_doctor, ->(doctor_profile) { where(doctor_profile: doctor_profile) }
  scope :of_type, ->(sncr_type) { where(sncr_type: sncr_type) }
  scope :of_endpoint, ->(endpoint) { where(endpoint: endpoint) }
  scope :succeeded, -> { where(status: "succeeded") }
  scope :requested_between, ->(from, to) { where(requested_at: from..to) }

  # O que pesa na cota da Anvisa. `failed` fica de fora de proposito: e recusa
  # antes do processamento (tipo invalido, inscricao divergente), e recusa nao
  # queima requisicao. `unknown` entra porque pode ter sido processado.
  scope :counts_against_quota, -> { where(status: %w[pending succeeded unknown]) }

  def self.endpoint_for(sncr_type)
    Sncr::NumberingBatch::ESPECIAL_TYPES.include?(sncr_type.to_s) ? "especial_retencao" : "notificacao"
  end

  def pending?
    status == "pending"
  end

  def succeeded?
    status == "succeeded"
  end

  # Peso na cota: o que a Anvisa entregou quando sabemos, o que pedimos quando
  # nao sabemos. Conservador por escolha.
  def quota_weight
    imported_count || requested_quantity
  end

  # Pendente ha tempo demais para ainda estar em voo.
  def stale_pending?(now: Time.current)
    pending? && requested_at < now - PENDING_GRACE
  end

  private

  def lifecycle_consistency
    case status
    when "pending"
      errors.add(:completed_at, "deve ser nulo enquanto pendente") if completed_at.present?
      errors.add(:imported_count, "deve ser nulo enquanto pendente") if imported_count.present?
    when "succeeded"
      errors.add(:completed_at, "deve estar presente quando concluída") if completed_at.blank?
      errors.add(:imported_count, "deve estar presente quando concluída") if imported_count.blank?
    when "failed", "unknown"
      errors.add(:completed_at, "deve estar presente quando concluída") if completed_at.blank?
    end
  end
end
