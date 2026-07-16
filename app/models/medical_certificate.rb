class MedicalCertificate < ApplicationRecord
  STATUSES = %w[draft signed cancelled].freeze

  attr_writer :rest_days

  belongs_to :user
  belongs_to :patient
  belongs_to :organization
  has_one :document, as: :documentable, dependent: :restrict_with_exception

  validates :code, presence: true, uniqueness: true, length: { minimum: 8 }
  validates :content, presence: true
  validates :issued_on, presence: true
  validates :rest_start_on, presence: true
  validates :rest_end_on, presence: true, comparison: { greater_than_or_equal_to: :rest_start_on }
  validates :rest_days, numericality: { only_integer: true, greater_than: 0 }, if: :rest_days_present?
  validates :status, inclusion: { in: STATUSES }

  normalizes :code, with: ->(value) { value&.strip&.upcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }
  normalizes :icd_code, with: ->(value) { value&.strip&.upcase }

  before_validation :assign_rest_end_on_from_rest_days
  before_validation :assign_default_organization
  before_validation :assign_default_user

  validate :organization_must_match_relations

  def rest_days
    return @rest_days if rest_days_present?
    return nil if rest_start_on.blank? || rest_end_on.blank?

    (rest_end_on - rest_start_on).to_i + 1
  end

  private

  def assign_rest_end_on_from_rest_days
    return if rest_start_on.blank? || rest_days.blank?

    days = Integer(rest_days, exception: false)
    self.rest_end_on = rest_start_on + (days - 1).days if days&.positive?
  end

  def rest_days_present?
    defined?(@rest_days) && @rest_days.present?
  end

  def assign_default_organization
    self.organization_id ||= patient&.organization_id || user&.current_organization_id
  end

  def assign_default_user
    self.user_id ||= patient&.user_id || Current.user&.id
  end

  def organization_must_match_relations
    return if organization_id.nil?
    return if patient.nil? || user.nil?
    return if patient.organization_id == organization_id && user.membership_for(organization_id).present?

    errors.add(:organization_id, "must match patient and user organization context")
  end
end
