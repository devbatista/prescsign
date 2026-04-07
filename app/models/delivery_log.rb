class DeliveryLog < ApplicationRecord
  CHANNELS = %w[email sms whatsapp].freeze
  STATUSES = %w[queued processing sent delivered failed].freeze

  belongs_to :doctor, optional: true
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
end
