class IdempotencyKey < ApplicationRecord
  belongs_to :doctor
  belongs_to :organization

  validates :scope, presence: true
  validates :key, presence: true
  validates :request_fingerprint, presence: true
  validates :key, uniqueness: { scope: %i[doctor_id organization_id scope] }
end
