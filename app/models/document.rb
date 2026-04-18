class Document < ApplicationRecord
  KINDS = %w[prescription medical_certificate].freeze
  STATUSES = %w[issued sent viewed revoked expired].freeze
  STATUS_ENUM = STATUSES.index_with(&:itself).freeze

  enum :status, STATUS_ENUM, suffix: true

  belongs_to :doctor
  belongs_to :user
  belongs_to :patient
  belongs_to :organization
  belongs_to :unit
  belongs_to :documentable, polymorphic: true

  has_many :document_versions, dependent: :restrict_with_exception
  has_many :delivery_logs, dependent: :nullify

  validates :kind, inclusion: { in: KINDS }
  validates :code, presence: true, uniqueness: true, length: { minimum: 8 }
  validates :status, inclusion: { in: STATUS_ENUM.values }
  validates :issued_on, presence: true
  validates :current_version, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validate :documentable_type_matches_kind
  validate :organization_must_match_relations
  validate :unit_must_belong_to_organization

  normalizes :kind, with: ->(value) { value&.strip&.downcase }
  normalizes :code, with: ->(value) { value&.strip&.upcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }

  before_validation :assign_default_organization
  before_validation :assign_default_unit
  before_validation :assign_default_user

  private

  def assign_default_organization
    self.organization_id ||= patient&.organization_id || user&.current_organization_id || doctor&.current_organization_id
  end

  def assign_default_unit
    self.unit_id ||= organization&.default_unit&.id
  end

  def assign_default_user
    self.user_id ||= patient&.user_id || doctor&.user&.id
    self.doctor_id ||= user&.doctor_id
  end

  def documentable_type_matches_kind
    expected_type = {
      "prescription" => "Prescription",
      "medical_certificate" => "MedicalCertificate"
    }[kind]
    return if expected_type.blank? || documentable_type == expected_type

    errors.add(:documentable_type, "must match document kind")
  end

  def organization_must_match_relations
    return if organization_id.nil?
    return if patient.nil? || user.nil?

    valid = patient.organization_id == organization_id &&
      user.membership_for(organization_id).present?
    valid &&= !documentable.respond_to?(:organization_id) || documentable.organization_id == organization_id

    return if valid

    errors.add(:organization_id, "must match patient, doctor and documentable organization")
  end

  def unit_must_belong_to_organization
    return if unit.nil? || organization_id.nil?
    return if unit.organization_id == organization_id

    errors.add(:unit_id, "must belong to the same organization")
  end
end
