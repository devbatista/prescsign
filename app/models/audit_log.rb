class AuditLog < ApplicationRecord
  ACTIONS = %w[created updated signed sent viewed revoked status_changed].freeze

  belongs_to :actor, polymorphic: true, optional: true
  belongs_to :organization, optional: true
  belongs_to :unit, optional: true
  belongs_to :patient, optional: true
  belongs_to :document, optional: true
  belongs_to :resource, polymorphic: true

  validates :action, presence: true, inclusion: { in: ACTIONS }
  validates :occurred_at, presence: true

  normalizes :action, with: ->(value) { value&.strip&.downcase }

  before_validation :assign_default_organization

  private

  def assign_default_organization
    self.organization_id ||= document&.organization_id
    self.organization_id ||= patient&.organization_id
    self.organization_id ||= actor.current_organization_id if actor.is_a?(Doctor)
    self.unit_id ||= document&.unit_id
  end
end
