class DoctorProfile < ApplicationRecord
  belongs_to :user
  belongs_to :doctor, optional: true

  validates :license_number, presence: true
  validates :license_state, presence: true, length: { is: 2 }
  validates :cpf, uniqueness: true, allow_blank: true, length: { minimum: 11 }

  normalizes :cpf, with: ->(value) { value&.gsub(/\D/, "") }
  normalizes :license_number, with: ->(value) { value&.strip&.upcase }
  normalizes :license_state, with: ->(value) { value&.strip&.upcase }
  normalizes :specialty, with: ->(value) { value&.strip }
end
