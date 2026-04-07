class MedicalCertificate < ApplicationRecord
  STATUSES = %w[draft signed cancelled].freeze

  belongs_to :doctor
  belongs_to :patient

  validates :code, presence: true, uniqueness: true, length: { minimum: 8 }
  validates :content, presence: true
  validates :issued_on, presence: true
  validates :rest_start_on, presence: true
  validates :rest_end_on, presence: true, comparison: { greater_than_or_equal_to: :rest_start_on }
  validates :status, inclusion: { in: STATUSES }

  normalizes :code, with: ->(value) { value&.strip&.upcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }
  normalizes :icd_code, with: ->(value) { value&.strip&.upcase }
end
