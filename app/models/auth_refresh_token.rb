class AuthRefreshToken < ApplicationRecord
  belongs_to :doctor

  scope :active, -> { where(revoked_at: nil).where("expires_at > ?", Time.current) }

  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  def revoke!
    update!(revoked_at: Time.current)
  end
end
