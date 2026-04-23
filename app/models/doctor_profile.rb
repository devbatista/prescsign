class DoctorProfile < ApplicationRecord
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

  validates :full_name, presence: true, length: { minimum: 3 }
  validates :active, inclusion: { in: [ true, false ] }
  validates :license_number, presence: true
  validates :license_state, presence: true, length: { is: 2 }
  validates :cpf, uniqueness: true, allow_blank: true, length: { minimum: 11 }
  validates :email, uniqueness: { case_sensitive: false }, allow_blank: true
  validates :gender, inclusion: { in: GENDERS }, allow_blank: true

  normalizes :full_name, with: ->(value) { value&.strip }
  normalizes :cpf, with: ->(value) { value&.gsub(/\D/, "") }
  normalizes :email, with: ->(value) { value&.strip&.downcase }
  normalizes :license_number, with: ->(value) { value&.strip&.upcase }
  normalizes :license_state, with: ->(value) { value&.strip&.upcase }
  normalizes :specialty, with: ->(value) { value&.strip }
  normalizes :gender, with: ->(value) { DoctorProfile.normalize_gender_input(value) }

  def professional_title
    female? ? "Dra." : "Dr."
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

  def resolved_gender
    return gender if GENDERS.include?(gender)

    normalized_name = full_name.to_s.downcase.strip
    return "female" if normalized_name.start_with?("dra")

    "male"
  end
end
