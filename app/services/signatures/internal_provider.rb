require "digest"

module Signatures
  class InternalProvider
    VERSION = "internal-v1".freeze

    def sign(content:, principal_id:, occurred_at:)
      payload = [content.to_s, principal_id.to_s, occurred_at.to_i.to_s, VERSION].join("|")
      Digest::SHA256.hexdigest(payload)
    end
  end
end
