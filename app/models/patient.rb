class Patient < ApplicationRecord
  belongs_to :doctor
  belongs_to :organization

  has_many :prescriptions, dependent: :restrict_with_exception
  has_many :medical_certificates, dependent: :restrict_with_exception
  has_many :documents, dependent: :restrict_with_exception
  has_many :delivery_logs, dependent: :nullify

  validates :full_name, presence: true, length: { minimum: 3 }
  validates :cpf, presence: true, uniqueness: { scope: :organization_id }, length: { minimum: 11 }
  validates :birth_date, presence: true
  validates :email, uniqueness: { case_sensitive: false }, allow_blank: true
  validates :phone, length: { minimum: 10 }, allow_blank: true

  normalizes :cpf, with: ->(value) { value&.gsub(/\D/, "") }
  normalizes :email, with: ->(value) { value&.strip&.downcase }
  normalizes :phone, with: ->(value) { value&.gsub(/\D/, "") }

  before_validation :assign_default_organization

  validate :organization_must_match_doctor

  private

  def assign_default_organization
    self.organization_id ||= doctor&.current_organization_id
  end

  def organization_must_match_doctor
    return if doctor.nil? || organization_id.nil?
    return if doctor.membership_for(organization_id).present?

    errors.add(:organization_id, "must belong to one of doctor's organizations")
  end
end
