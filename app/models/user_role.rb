class UserRole < ApplicationRecord
  ROLES = %w[doctor admin support manager super_admin].freeze
  STATUSES = %w[active inactive].freeze

  belongs_to :user
  scope :active, -> { where(status: "active") }

  validates :role, presence: true, inclusion: { in: ROLES }, uniqueness: { scope: :user_id }
  validates :status, presence: true, inclusion: { in: STATUSES }

  normalizes :role, with: ->(value) { value&.strip&.downcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }
end
