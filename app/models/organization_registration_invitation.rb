require "digest"

class OrganizationRegistrationInvitation < ApplicationRecord
  INVITATION_TTL = 7.days

  belongs_to :organization
  belongs_to :invited_by_user, class_name: "User", optional: true
  belongs_to :accepted_by_user, class_name: "User", optional: true

  validates :invited_email, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :expires_at, presence: true

  normalizes :invited_email, with: ->(value) { value&.strip&.downcase }

  scope :pending, -> { where(accepted_at: nil).where("expires_at > ?", Time.current) }

  def expired?
    expires_at <= Time.current
  end

  def accepted?
    accepted_at.present?
  end

  def mark_accepted!(user:)
    update!(accepted_at: Time.current, accepted_by_user: user)
  end

  def self.issue!(organization:, invited_email:, invited_by_user: nil)
    raw_token = SecureRandom.urlsafe_base64(48)

    invitation = create!(
      organization: organization,
      invited_by_user: invited_by_user,
      invited_email: invited_email,
      token_digest: digest_token(raw_token),
      expires_at: INVITATION_TTL.from_now
    )

    [invitation, raw_token]
  end

  def self.find_pending_by_raw_token(raw_token)
    return nil if raw_token.blank?

    pending.find_by(token_digest: digest_token(raw_token.to_s))
  end

  def self.digest_token(raw_token)
    Digest::SHA256.hexdigest(raw_token.to_s)
  end
end
