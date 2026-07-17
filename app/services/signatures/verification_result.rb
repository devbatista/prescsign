module Signatures
  VerificationResult = Data.define(
    :provider,
    :valid,
    :validation_status,
    :signatures,
    :checked_at,
    :raw_metadata
  ) do
    def initialize(
      provider:,
      valid: nil,
      validation_status: nil,
      signatures: [],
      checked_at: Time.current,
      raw_metadata: {}
    )
      super
    end
  end
end
