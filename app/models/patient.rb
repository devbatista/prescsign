class Patient < ApplicationRecord
  has_many :prescriptions, dependent: :restrict_with_exception
  has_many :medical_certificates, dependent: :restrict_with_exception
  has_many :documents, dependent: :restrict_with_exception
  has_many :delivery_logs, dependent: :nullify

  validates :full_name, presence: true, length: { minimum: 3 }
  validates :cpf, presence: true, uniqueness: true, length: { minimum: 11 }
  validates :birth_date, presence: true
  validates :email, uniqueness: { case_sensitive: false }, allow_blank: true
  validates :phone, length: { minimum: 10 }, allow_blank: true

  normalizes :cpf, with: ->(value) { value&.gsub(/\D/, "") }
  normalizes :email, with: ->(value) { value&.strip&.downcase }
  normalizes :phone, with: ->(value) { value&.gsub(/\D/, "") }
end
