require "rails_helper"

RSpec.describe DocumentVersion, type: :model do
  describe "#pdf_signed_url" do
    it "returns nil outside production" do
      version = described_class.new
      attachment = double("attachment", attached?: true)

      allow(version).to receive(:pdf_file).and_return(attachment)

      expect(version.pdf_signed_url).to be_nil
    end

    it "returns an expiring signed URL in production when attached" do
      version = described_class.new
      attachment = double("attachment")
      blob = double("blob")
      expires_in = version.pdf_signed_url_expires_in

      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      allow(version).to receive(:pdf_file).and_return(attachment)
      allow(attachment).to receive(:attached?).and_return(true)
      allow(attachment).to receive(:blob).and_return(blob)
      allow(blob).to receive(:filename).and_return("prescription.pdf")
      allow(attachment).to receive(:url).with(
        expires_in: expires_in,
        disposition: "inline",
        filename: "prescription.pdf"
      ).and_return("https://signed.example.com/path")

      expect(version.pdf_signed_url).to eq("https://signed.example.com/path")
    end
  end
end
