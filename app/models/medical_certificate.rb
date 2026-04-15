class MedicalCertificate < ApplicationRecord
  STATUSES = %w[draft signed cancelled].freeze

  belongs_to :doctor
  belongs_to :patient
  belongs_to :organization
  has_one :document, as: :documentable, dependent: :restrict_with_exception

  validates :code, presence: true, uniqueness: true, length: { minimum: 8 }
  validates :content, presence: true
  validates :issued_on, presence: true
  validates :rest_start_on, presence: true
  validates :rest_end_on, presence: true, comparison: { greater_than_or_equal_to: :rest_start_on }
  validates :status, inclusion: { in: STATUSES }

  normalizes :code, with: ->(value) { value&.strip&.upcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }
  normalizes :icd_code, with: ->(value) { value&.strip&.upcase }

  before_validation :assign_default_organization

  validate :organization_must_match_relations

  private

  def assign_default_organization
    self.organization_id ||= patient&.organization_id || doctor&.current_organization_id
  end

  def organization_must_match_relations
    return if organization_id.nil?
    return if patient.nil? || doctor.nil?
    return if patient.organization_id == organization_id && doctor.membership_for(organization_id).present?

    errors.add(:organization_id, "must match patient and doctor organization context")
  end
end
