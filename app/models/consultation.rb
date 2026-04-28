class Consultation < ApplicationRecord
  STATUSES = %w[scheduled completed cancelled].freeze
  STATUS_ENUM = STATUSES.index_with(&:itself).freeze

  enum :status, STATUS_ENUM, suffix: true

  belongs_to :patient
  belongs_to :user
  belongs_to :organization

  validates :scheduled_at, presence: true
  validates :status, inclusion: { in: STATUS_ENUM.values }
  validate :finished_at_must_be_after_scheduled_at
  validate :organization_must_match_relations

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
    self.user_id ||= patient&.user_id || Current.user&.id
  end

  def finished_at_must_be_after_scheduled_at
    return if finished_at.blank? || scheduled_at.blank?
    return if finished_at >= scheduled_at

    errors.add(:finished_at, "must be greater than or equal to scheduled_at")
  end

  def organization_must_match_relations
    return if organization_id.blank?
    return if patient.nil? || user.nil?

    valid = patient.organization_id == organization_id
    valid &&= user.membership_for(organization_id).present?
    return if valid

    errors.add(:organization_id, "must match patient and user organization")
  end
end
