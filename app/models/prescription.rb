class Prescription < ApplicationRecord
  STATUSES = %w[draft signed cancelled].freeze

  belongs_to :doctor
  belongs_to :user
  belongs_to :patient
  belongs_to :organization
  has_one :document, as: :documentable, dependent: :restrict_with_exception

  validates :code, presence: true, uniqueness: true, length: { minimum: 8 }
  validates :content, presence: true
  validates :issued_on, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :valid_until, comparison: { greater_than_or_equal_to: :issued_on }, allow_nil: true

  normalizes :code, with: ->(value) { value&.strip&.upcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }

  before_validation :assign_default_organization
  before_validation :assign_default_user

  validate :organization_must_match_relations

  private

  def assign_default_organization
    self.organization_id ||= patient&.organization_id || user&.current_organization_id || doctor&.current_organization_id
  end

  def assign_default_user
    self.user_id ||= patient&.user_id || doctor&.user&.id
    self.doctor_id ||= user&.doctor_id
  end

  def organization_must_match_relations
    return if organization_id.nil?
    return if patient.nil? || user.nil?
    return if patient.organization_id == organization_id && user.membership_for(organization_id).present?

    errors.add(:organization_id, "must match patient and doctor organization context")
  end
end
