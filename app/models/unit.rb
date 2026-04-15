class Unit < ApplicationRecord
  belongs_to :organization

  has_many :documents, dependent: :restrict_with_exception
  has_many :audit_logs, dependent: :nullify

  validates :name, presence: true, uniqueness: { scope: :organization_id }

  scope :active, -> { where(active: true) }

  normalizes :name, with: ->(value) { value&.strip }
  normalizes :code, with: ->(value) { value&.strip&.upcase }
end
