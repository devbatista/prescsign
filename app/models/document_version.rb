class DocumentVersion < ApplicationRecord
  TIMESTAMP_FORMAT = "%Y%m%dT%H%M%SZ".freeze

  belongs_to :document

  validates :version_number, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :content, presence: true
  validates :checksum, length: { minimum: 16 }, allow_blank: true

  def pdf_storage_directory
    "documents/#{document_id}/v#{version_number}"
  end

  def pdf_storage_filename(timestamp: generated_at || Time.current)
    "#{document.kind}_#{timestamp.utc.strftime(TIMESTAMP_FORMAT)}.pdf"
  end

  def pdf_storage_key(timestamp: generated_at || Time.current)
    "#{pdf_storage_directory}/#{pdf_storage_filename(timestamp: timestamp)}"
  end
end
