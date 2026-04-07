class Document < ApplicationRecord
  KINDS = %w[prescription medical_certificate].freeze
  STATUSES = %w[issued sent viewed revoked expired].freeze
  STATUS_ENUM = STATUSES.index_with(&:itself).freeze

  enum :status, STATUS_ENUM, suffix: true

  belongs_to :doctor
  belongs_to :patient
  belongs_to :documentable, polymorphic: true

  has_many :document_versions, dependent: :restrict_with_exception
  has_many :delivery_logs, dependent: :nullify

  validates :kind, inclusion: { in: KINDS }
  validates :code, presence: true, uniqueness: true, length: { minimum: 8 }
  validates :status, inclusion: { in: STATUS_ENUM.values }
  validates :issued_on, presence: true
  validates :current_version, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validate :documentable_type_matches_kind

  normalizes :kind, with: ->(value) { value&.strip&.downcase }
  normalizes :code, with: ->(value) { value&.strip&.upcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }

  private

  def documentable_type_matches_kind
    expected_type = {
      "prescription" => "Prescription",
      "medical_certificate" => "MedicalCertificate"
    }[kind]
    return if expected_type.blank? || documentable_type == expected_type

    errors.add(:documentable_type, "must match document kind")
  end
end
