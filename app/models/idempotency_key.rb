class IdempotencyKey < ApplicationRecord
  belongs_to :user
  belongs_to :organization

  validates :scope, presence: true
  validates :key, presence: true
  validates :request_fingerprint, presence: true
  validates :key, uniqueness: { scope: %i[user_id organization_id scope] }

  before_validation :assign_default_user

  private

  def assign_default_user
    self.user_id ||= Current.user&.id
  end
end
