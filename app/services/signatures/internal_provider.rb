require "digest"

module Signatures
  class InternalProvider
    VERSION = "internal-v1".freeze

    def sign(content:, principal_id:, occurred_at:)
      payload = [content.to_s, principal_id.to_s, occurred_at.to_i.to_s, VERSION].join("|")
      Digest::SHA256.hexdigest(payload)
    end

    def sign_pdf!(document:, pdf_io:, signer:)
      signed_at = Time.current
      content = document.documentable.content.to_s

      SignatureResult.new(
        signed_pdf: pdf_io.read,
        provider: "internal",
        method: "internal_mvp",
        signed_at: signed_at,
        timestamped: false,
        validation_status: "not_applicable",
        raw_metadata: {
          "value" => sign(content: content, principal_id: signer.id, occurred_at: signed_at),
          "provider_version" => VERSION,
          "signed_content_checksum" => Digest::SHA256.hexdigest(content)
        }
      )
    end
  end
end
