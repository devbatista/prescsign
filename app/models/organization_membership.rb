class OrganizationMembership < ApplicationRecord
  ROLES = %w[owner admin doctor staff].freeze
  STATUSES = %w[active inactive].freeze

  belongs_to :doctor
  belongs_to :organization

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :doctor_id, uniqueness: { scope: :organization_id }

  scope :active, -> { where(status: "active") }

  normalizes :role, with: ->(value) { value&.strip&.downcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }
end
