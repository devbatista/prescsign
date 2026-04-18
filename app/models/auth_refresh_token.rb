class AuthRefreshToken < ApplicationRecord
  belongs_to :doctor
  belongs_to :user

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  before_validation :assign_default_user

  def revoke!
    update!(revoked_at: Time.current)
  end

  private

  def assign_default_user
    self.user_id ||= doctor&.user&.id
  end
end
