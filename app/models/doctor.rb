class Doctor < ApplicationRecord
  devise :database_authenticatable,
         :registerable,
         :recoverable,
         :confirmable,
         :jwt_authenticatable,
         jwt_revocation_strategy: JwtDenylist

  has_many :auth_refresh_tokens, dependent: :delete_all
  belongs_to :current_organization, class_name: "Organization", optional: true
  has_many :organization_memberships, dependent: :restrict_with_exception
  has_many :organizations, through: :organization_memberships
  has_many :organization_responsibles, dependent: :nullify
  has_one :doctor_profile, dependent: :nullify
  has_many :patients, dependent: :restrict_with_exception
  has_many :prescriptions, dependent: :restrict_with_exception
  has_many :medical_certificates, dependent: :restrict_with_exception
  has_many :documents, dependent: :restrict_with_exception
  has_many :audit_logs, as: :actor, dependent: :nullify
  has_many :delivery_logs, dependent: :nullify

  validates :full_name, presence: true, length: { minimum: 3 }
  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :cpf, presence: true, uniqueness: true, length: { minimum: 11 }
  validates :license_number, presence: true
  validates :license_state, presence: true, length: { is: 2 }
  validates :password, length: { minimum: 8 }, allow_nil: true

  normalizes :email, with: ->(value) { value.strip.downcase }
  normalizes :license_state, with: ->(value) { value.strip.upcase }

  after_create :ensure_personal_organization!

  def active_organization_memberships
    organization_memberships.active
  end

  def membership_for(organization_id)
    return nil if organization_id.blank?

    active_organization_memberships.find_by(organization_id: organization_id)
  end

  def organization_role(organization_id = current_organization_id)
    membership_for(organization_id)&.role
  end

  def organization_admin?(organization_id = current_organization_id)
    %w[owner admin].include?(organization_role(organization_id))
  end

  def masked_cpf
    digits = cpf.to_s.gsub(/\D/, "")
    return nil if digits.length < 11

    "***.***.***-#{digits[-2, 2]}"
  end

  private

  def ensure_personal_organization!
    return if active_organization_memberships.exists?

    organization = Organization.create!(
      name: "Autônomo - #{full_name}",
      kind: "autonomo",
      active: true
    )

    organization_memberships.create!(
      organization: organization,
      role: "owner",
      status: "active"
    )

    update_column(:current_organization_id, organization.id)
  end
end
