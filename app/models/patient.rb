class Patient < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  has_many :prescriptions, dependent: :restrict_with_exception
  has_many :medical_certificates, dependent: :restrict_with_exception
  has_many :documents, dependent: :restrict_with_exception
  has_many :consultations, dependent: :restrict_with_exception
  has_many :delivery_logs, dependent: :nullify

  validates :full_name, presence: true, length: { minimum: 3 }
  validates :cpf, presence: true, uniqueness: { scope: :organization_id }, length: { minimum: 11 }
  validates :birth_date, presence: true
  validates :email, uniqueness: { scope: :organization_id, case_sensitive: false }, allow_blank: true
  validates :phone, length: { minimum: 10 }, allow_blank: true

  normalizes :cpf, with: ->(value) { value&.gsub(/\D/, "") }
  normalizes :email, with: ->(value) { value&.strip&.downcase }
  normalizes :phone, with: ->(value) { value&.gsub(/\D/, "") }

  before_validation :assign_default_organization
  before_validation :assign_default_user

  validate :organization_must_match_user

  private

  def assign_default_organization
    self.organization_id ||= user&.current_organization_id
  end

  def assign_default_user
    self.user_id ||= Current.user&.id
  end

  def organization_must_match_user
    acting_user = user
    return if acting_user.nil? || organization_id.nil?
    return if acting_user.membership_for(organization_id).present?

    errors.add(:organization_id, "must belong to one of user's organizations")
  end
end
