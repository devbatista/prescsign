require "digest"
require "securerandom"

module Auth
  class RefreshTokenService
    REFRESH_TOKEN_TTL = 30.days

    class << self
      def issue_for(user:)
        raw_token = SecureRandom.hex(64)

        AuthRefreshToken.create!(
          user: user,
          token_digest: digest(raw_token),
          expires_at: REFRESH_TOKEN_TTL.from_now
        )

        raw_token
      end

      def find_active(raw_token)
        AuthRefreshToken.active.find_by(token_digest: digest(raw_token))
      end

      def digest(raw_token)
        Digest::SHA256.hexdigest(raw_token.to_s)
      end
    end
  end
end
