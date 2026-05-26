require "rails_helper"
require "digest"
require "stringio"

RSpec.describe Signatures::InternalProvider do
  describe "#sign_pdf!" do
    it "returns the original PDF with internal audit metadata" do
      document = instance_double(
        Document,
        documentable: instance_double(Prescription, content: "Receita teste")
      )
      signer = instance_double(User, id: "user-123")

      result = described_class.new.sign_pdf!(
        document: document,
        pdf_io: StringIO.new("%PDF unsigned"),
        signer: signer
      )

      expect(result.signed_pdf).to eq("%PDF unsigned")
      expect(result.provider).to eq("internal")
      expect(result.method).to eq("internal_mvp")
      expect(result.raw_metadata["provider_version"]).to eq(described_class::VERSION)
      expect(result.raw_metadata["signed_content_checksum"]).to eq(Digest::SHA256.hexdigest("Receita teste"))
    end
  end
end
