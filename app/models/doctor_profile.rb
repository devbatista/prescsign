class DoctorProfile < ApplicationRecord
  belongs_to :user

  validates :full_name, presence: true, length: { minimum: 3 }
  validates :active, inclusion: { in: [ true, false ] }
  validates :license_number, presence: true
  validates :license_state, presence: true, length: { is: 2 }
  validates :cpf, uniqueness: true, allow_blank: true, length: { minimum: 11 }
  validates :email, uniqueness: { case_sensitive: false }, allow_blank: true

  normalizes :full_name, with: ->(value) { value&.strip }
  normalizes :cpf, with: ->(value) { value&.gsub(/\D/, "") }
  normalizes :email, with: ->(value) { value&.strip&.downcase }
  normalizes :license_number, with: ->(value) { value&.strip&.upcase }
  normalizes :license_state, with: ->(value) { value&.strip&.upcase }
  normalizes :specialty, with: ->(value) { value&.strip }
end
