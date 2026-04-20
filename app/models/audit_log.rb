class AuditLog < ApplicationRecord
  ACTIONS = %w[created updated signed sent viewed revoked status_changed].freeze

  belongs_to :actor, polymorphic: true, optional: true
  belongs_to :user, optional: true
  belongs_to :organization, optional: true
  belongs_to :unit, optional: true
  belongs_to :patient, optional: true
  belongs_to :document, optional: true
  belongs_to :resource, polymorphic: true

  validates :action, presence: true, inclusion: { in: ACTIONS }
  validates :occurred_at, presence: true

  normalizes :action, with: ->(value) { value&.strip&.downcase }

  before_validation :assign_default_organization

  class << self
    def record!(**attributes)
      AuditLogs::Recorder.call(**attributes)
    end
  end

  private

  def assign_default_organization
    self.user_id ||= actor.id if actor.is_a?(User)
    self.user_id ||= document&.user_id
    self.user_id ||= patient&.user_id
    self.organization_id ||= document&.organization_id
    self.organization_id ||= patient&.organization_id
    self.organization_id ||= actor.current_organization_id if actor.respond_to?(:current_organization_id)
    self.unit_id ||= document&.unit_id
  end
end
