require "rails_helper"
require "securerandom"

RSpec.describe "DocumentVersion naming" do
  it "builds storage key with document id, version and timestamp" do
    document_id = SecureRandom.uuid
    generated_at = Time.zone.parse("2026-04-14 12:34:56 UTC")
    document = Document.new(id: document_id, kind: "prescription")
    version = DocumentVersion.new(
      document: document,
      document_id: document_id,
      version_number: 2,
      generated_at: generated_at
    )

    expect(version.pdf_storage_directory).to eq("documents/#{document_id}/v2")
    expect(version.pdf_storage_filename).to eq("prescription_20260414T123456Z.pdf")
    expect(version.pdf_storage_key).to eq("documents/#{document_id}/v2/prescription_20260414T123456Z.pdf")
  end
end
