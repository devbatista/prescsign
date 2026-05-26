module Signatures
  SignatureResult = Data.define(
    :signed_pdf,
    :provider,
    :method,
    :policy,
    :certificate_subject,
    :certificate_issuer,
    :certificate_serial,
    :certificate_cpf,
    :signed_at,
    :timestamped,
    :validation_status,
    :raw_metadata
  ) do
    def initialize(
      signed_pdf:,
      provider:,
      method:,
      policy: nil,
      certificate_subject: nil,
      certificate_issuer: nil,
      certificate_serial: nil,
      certificate_cpf: nil,
      signed_at: Time.current,
      timestamped: false,
      validation_status: nil,
      raw_metadata: {}
    )
      super
    end
  end
end
