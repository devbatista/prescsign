class IdempotencyKey < ApplicationRecord
  belongs_to :doctor
  belongs_to :user
  belongs_to :organization

  validates :scope, presence: true
  validates :key, presence: true
  validates :request_fingerprint, presence: true
  validates :key, uniqueness: { scope: %i[user_id organization_id scope] }

  before_validation :assign_default_user
  before_validation :assign_default_doctor

  private

  def assign_default_user
    self.user_id ||= doctor&.user&.id
  end

  def assign_default_doctor
    self.doctor_id ||= user&.doctor_id
  end
end
