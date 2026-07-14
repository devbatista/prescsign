class Consultation < ApplicationRecord
  STATUSES = %w[scheduled completed cancelled].freeze
  STATUS_ENUM = STATUSES.index_with(&:itself).freeze
  ALLOWED_STATUS_TRANSITIONS = {
    "scheduled" => %w[completed cancelled],
    "completed" => [],
    "cancelled" => []
  }.freeze

  enum :status, STATUS_ENUM, suffix: true

  belongs_to :patient
  belongs_to :user, optional: true
  belongs_to :organization
  belongs_to :specialty, optional: true

  validates :scheduled_at, presence: true
  validates :specialty, presence: true, on: :create
  validates :status, inclusion: { in: STATUS_ENUM.values }
  validate :finished_at_must_be_after_scheduled_at
  validate :organization_must_match_relations
  validate :patient_must_be_active, on: :create
  validate :professional_must_match_specialty
  validate :status_transition_must_be_allowed, on: :update

  normalizes :status, with: ->(value) { value&.strip&.downcase }

  before_validation :assign_default_organization
  before_validation :assign_default_user

  scope :recent_first, -> { order(scheduled_at: :desc, created_at: :desc) }
  scope :with_status, ->(value) { value.present? ? where(status: value) : all }
  scope :scheduled_between, lambda { |from, to|
    scoped = all
    scoped = scoped.where("scheduled_at >= ?", from) if from.present?
    scoped = scoped.where("scheduled_at <= ?", to) if to.present?
    scoped
  }

  private

  def assign_default_organization
    self.organization_id ||= patient&.organization_id || user&.current_organization_id
  end

  def assign_default_user
    return if user_id.present?
    return unless Current.user&.has_role?("doctor")

    self.user_id = Current.user.id
  end

  def finished_at_must_be_after_scheduled_at
    return if finished_at.blank? || scheduled_at.blank?
    return if finished_at >= scheduled_at

    errors.add(:finished_at, "must be greater than or equal to scheduled_at")
  end

  def organization_must_match_relations
    return if organization_id.blank?
    return if patient.nil?

    valid = patient.organization_id == organization_id
    valid &&= user.membership_for(organization_id).present? if user.present?
    return if valid

    errors.add(:organization_id, "must match patient and user organization")
  end

  def patient_must_be_active
    return if patient.blank? || patient.active?

    errors.add(:patient_id, "must be active")
  end

  def professional_must_match_specialty
    return if user.blank? || specialty.blank?
    return if user.doctor_profile.blank?
    return if user.doctor_profile.specialties.exists?(id: specialty_id)

    errors.add(:user_id, "must be linked to the selected specialty")
  end

  def status_transition_must_be_allowed
    return unless will_save_change_to_status?

    from_status, to_status = status_change_to_be_saved
    return if from_status.blank? || to_status.blank? || from_status == to_status
    return if ALLOWED_STATUS_TRANSITIONS.fetch(from_status, []).include?(to_status)

    errors.add(:status, "transition from #{from_status} to #{to_status} is not allowed")
  end
end
