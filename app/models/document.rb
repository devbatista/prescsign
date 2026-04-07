class Document < ApplicationRecord
  KINDS = %w[prescription medical_certificate].freeze
  STATUSES = %w[draft signed cancelled].freeze

  belongs_to :doctor
  belongs_to :patient
  belongs_to :documentable, polymorphic: true

  has_many :document_versions, dependent: :restrict_with_exception

  validates :kind, inclusion: { in: KINDS }
  validates :code, presence: true, uniqueness: true, length: { minimum: 8 }
  validates :status, inclusion: { in: STATUSES }
  validates :issued_on, presence: true
  validates :current_version, numericality: { only_integer: true, greater_than_or_equal_to: 1 }

  normalizes :kind, with: ->(value) { value&.strip&.downcase }
  normalizes :code, with: ->(value) { value&.strip&.upcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }
end
