class Prescription < ApplicationRecord
  STATUSES = %w[draft signed cancelled].freeze

  belongs_to :doctor
  belongs_to :patient
  has_one :document, as: :documentable, dependent: :restrict_with_exception

  validates :code, presence: true, uniqueness: true, length: { minimum: 8 }
  validates :content, presence: true
  validates :issued_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :valid_until, comparison: { greater_than_or_equal_to: :issued_on }, allow_nil: true

  normalizes :code, with: ->(value) { value&.strip&.upcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }
end
