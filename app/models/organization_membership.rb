class OrganizationMembership < ApplicationRecord
  # Papéis DE ORGANIZAÇÃO. `owner` é o responsável/administrador da org — não
  # existe papel "admin" aqui: `admin` é papel de PLATAFORMA (back-office),
  # gerido em user_roles, não em membership.
  ROLES = %w[owner doctor staff].freeze
  STATUSES = %w[active inactive].freeze

  belongs_to :user
  belongs_to :organization

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :organization_id }

  scope :active, -> { where(status: "active") }

  normalizes :role, with: ->(value) { value&.strip&.downcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }

end
