class DeliveryLog < ApplicationRecord
  CHANNELS = %w[email sms whatsapp].freeze
  STATUSES = %w[queued processing sent delivered failed].freeze

  belongs_to :doctor, optional: true
  belongs_to :user, optional: true
  belongs_to :organization, optional: true
  belongs_to :patient, optional: true
  belongs_to :document, optional: true

  validates :channel, presence: true, inclusion: { in: CHANNELS }
  validates :status, presence: true, inclusion: { in: STATUSES }
  validates :attempted_at, presence: true
  validates :recipient, presence: true
  validates :error_message, presence: true, if: -> { status == "failed" }
  validates :delivered_at, presence: true, if: -> { status == "delivered" }

  normalizes :channel, with: ->(value) { value&.strip&.downcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }

  before_validation :assign_default_organization
  before_validation :assign_default_user

  private

  def assign_default_organization
    self.organization_id ||= document&.organization_id
    self.organization_id ||= patient&.organization_id
    self.organization_id ||= user&.current_organization_id
    self.organization_id ||= doctor&.current_organization_id
  end

  def assign_default_user
    self.user_id ||= document&.user_id
    self.user_id ||= patient&.user_id
    self.user_id ||= doctor&.user&.id
    self.doctor_id ||= user&.doctor_id
  end
end
