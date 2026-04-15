require "stringio"

class DocumentVersion < ApplicationRecord
  TIMESTAMP_FORMAT = "%Y%m%dT%H%M%SZ".freeze

  belongs_to :document
  has_one_attached :pdf_file

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

  def attach_pdf!(pdf_binary)
    timestamp = generated_at || Time.current

    pdf_file.attach(
      io: StringIO.new(pdf_binary),
      filename: pdf_storage_filename(timestamp: timestamp),
      content_type: "application/pdf",
      key: pdf_storage_key(timestamp: timestamp)
    )
  end
end
