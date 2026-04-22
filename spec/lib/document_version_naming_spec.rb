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

  it "builds unique storage keys for repeated PDF attachments of the same version" do
    document_id = SecureRandom.uuid
    generated_at = Time.zone.parse("2026-04-14 12:34:56 UTC")
    document = Document.new(id: document_id, kind: "medical_certificate")
    version = DocumentVersion.new(
      document: document,
      document_id: document_id,
      version_number: 2,
      generated_at: generated_at
    )

    first_key = version.pdf_unique_storage_key
    second_key = version.pdf_unique_storage_key

    expect(first_key).to start_with("documents/#{document_id}/v2/")
    expect(first_key).to end_with("_medical_certificate_20260414T123456Z.pdf")
    expect(second_key).to start_with("documents/#{document_id}/v2/")
    expect(second_key).to end_with("_medical_certificate_20260414T123456Z.pdf")
    expect(first_key).not_to eq(second_key)
  end
end
