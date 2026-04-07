class Doctor < ApplicationRecord
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

  normalizes :email, with: ->(value) { value.strip.downcase }
  normalizes :license_state, with: ->(value) { value.strip.upcase }
end
