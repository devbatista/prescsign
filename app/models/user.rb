class User < ApplicationRecord
  STATUSES = %w[active inactive blocked].freeze

  devise :database_authenticatable,
         :recoverable,
         :confirmable,
         :jwt_authenticatable,
         jwt_revocation_strategy: JwtDenylist

  has_many :user_roles, dependent: :delete_all
  has_one :doctor_profile, dependent: :destroy
  has_many :legacy_doctor_user_mappings, dependent: :delete_all
  has_many :organization_responsibles, dependent: :nullify
  has_many :organization_memberships, dependent: :restrict_with_exception
  has_many :patients, dependent: :restrict_with_exception
  has_many :prescriptions, dependent: :restrict_with_exception
  has_many :medical_certificates, dependent: :restrict_with_exception
  has_many :documents, dependent: :restrict_with_exception
  has_many :delivery_logs, dependent: :nullify
  has_many :idempotency_keys, dependent: :delete_all
  has_many :auth_refresh_tokens, dependent: :delete_all

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }

  normalizes :email, with: ->(value) { value&.strip&.downcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }

  def active_for_authentication?
    super && status == "active"
  end

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
    return nil if organization_id.blank?

    organization_memberships.active.find_by(organization_id: organization_id)
  end

  def organization_admin?(organization_id = current_organization_id)
    return true if has_role?("super_admin") || has_role?("admin") || has_role?("manager")

    %w[owner admin].include?(membership_for(organization_id)&.role)
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
