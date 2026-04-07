class AuditLog < ApplicationRecord
  ACTIONS = %w[created updated signed sent viewed revoked status_changed].freeze

  belongs_to :actor, polymorphic: true, optional: true
  belongs_to :patient, optional: true
  belongs_to :document, optional: true
  belongs_to :resource, polymorphic: true

  validates :action, presence: true, inclusion: { in: ACTIONS }
  validates :occurred_at, presence: true

  normalizes :action, with: ->(value) { value&.strip&.downcase }
end
