class User < ApplicationRecord
  STATUSES = %w[active inactive blocked].freeze

  has_many :user_roles, dependent: :delete_all
  has_one :doctor_profile, dependent: :destroy
  has_many :legacy_doctor_user_mappings, dependent: :delete_all
  has_many :organization_responsibles, dependent: :nullify

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }

  normalizes :email, with: ->(value) { value&.strip&.downcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }

  def doctor
    doctor_profile&.doctor
  end

  def doctor_id
    doctor&.id
  end

  def current_organization_id
    doctor&.current_organization_id
  end

  def membership_for(organization_id)
    doctor&.membership_for(organization_id)
  end

  def organization_admin?(organization_id = current_organization_id)
    return true if has_role?("super_admin") || has_role?("admin") || has_role?("manager")

    doctor&.organization_admin?(organization_id) || false
  end

  def admin?
    has_role?("super_admin") || has_role?("admin")
  end

  def support?
    has_role?("support")
  end

  def has_role?(role_name)
    user_roles.where(role: role_name.to_s, status: "active").exists?
  end
end
