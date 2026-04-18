class OrganizationMembership < ApplicationRecord
  ROLES = %w[owner admin doctor staff].freeze
  STATUSES = %w[active inactive].freeze

  belongs_to :doctor
  belongs_to :user
  belongs_to :organization

  validates :role, inclusion: { in: ROLES }
  validates :status, inclusion: { in: STATUSES }
  validates :user_id, uniqueness: { scope: :organization_id }

  before_validation :assign_default_user
  before_validation :assign_default_doctor

  scope :active, -> { where(status: "active") }

  normalizes :role, with: ->(value) { value&.strip&.downcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }

  private

  def assign_default_user
    self.user_id ||= doctor&.user&.id
  end

  def assign_default_doctor
    self.doctor_id ||= user&.doctor_id
  end
end
