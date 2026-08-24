class DoctorProfile < ApplicationRecord
  attr_accessor :license_organization_id

  GENDERS = %w[male female].freeze
  GENDER_INPUT_MAP = {
    "male" => "male",
    "m" => "male",
    "dr" => "male",
    "masculino" => "male",
    "female" => "female",
    "f" => "female",
    "dra" => "female",
    "feminino" => "female"
  }.freeze

  belongs_to :user

  has_many :doctor_specialties, dependent: :destroy
  has_many :specialties, through: :doctor_specialties
  has_many :sncr_numberings, dependent: :delete_all

  accepts_nested_attributes_for :doctor_specialties, allow_destroy: true,
    reject_if: ->(attrs) { attrs[:specialty_name].blank? && attrs[:specialty_id].blank? }

  validates :full_name, presence: true, length: { minimum: 3 }
  validates :active, inclusion: { in: [ true, false ] }
  validates :license_number, presence: true
  validates :license_state, presence: true, length: { is: 2 }
  validates :cpf, presence: true, uniqueness: true, length: { minimum: 11 }
  validates :email, uniqueness: { case_sensitive: false }, allow_blank: true
  validates :gender, inclusion: { in: GENDERS }, allow_blank: true
  validate :license_unique_within_organization

  normalizes :full_name, with: ->(value) { value&.strip }
  normalizes :cpf, with: ->(value) { value&.gsub(/\D/, "") }
  normalizes :email, with: ->(value) { value&.strip&.downcase }
  normalizes :license_number, with: ->(value) { value&.strip&.upcase }
  normalizes :license_state, with: ->(value) { value&.strip&.upcase }
  normalizes :gender, with: ->(value) { DoctorProfile.normalize_gender_input(value) }

  # Specialty names for display (ordered). Replaces the former free-text column.
  def specialty_names
    specialties.order(:name).pluck(:name)
  end

  # Human-readable specialties label (e.g. "Cardiologia · Clínica Médica").
  def specialty_label
    specialty_names.join(" · ")
  end

  def professional_title
    female? ? "Dra." : "Dr."
  end

  # Nome para exibição a terceiros (ex.: remetente do e-mail ao paciente). Não
  # reaplica o título quando o cadastro já veio com "Dr."/"Dra." digitado.
  def display_name
    return full_name if full_name.to_s.match?(/\Adra?\.?\s/i)

    "#{professional_title} #{full_name}"
  end

  def welcome_prefix
    female? ? "Bem-vinda" : "Bem-vindo"
  end

  def gender_label
    female? ? "Dra" : "Dr"
  end

  def female?
    resolved_gender == "female"
  end

  private

  def self.normalize_gender_input(value)
    raw = value&.to_s&.strip&.downcase
    return nil if raw.blank?

    GENDER_INPUT_MAP.fetch(raw, raw)
  end

  def license_unique_within_organization
    return if license_organization_id.blank?
    return if license_number.blank? || license_state.blank?

    matching_profile = self.class
      .joins(user: :organization_memberships)
      .where(license_number: license_number, license_state: license_state)
      .where(organization_memberships: {
        organization_id: license_organization_id,
        role: "doctor",
        status: "active"
      })
      .where.not(id: id)
      .exists?

    errors.add(:base, "CRM já existe para esta clínica.") if matching_profile
  end

  def resolved_gender
    return gender if GENDERS.include?(gender)

    normalized_name = full_name.to_s.downcase.strip
    return "female" if normalized_name.start_with?("dra")

    "male"
  end
end
