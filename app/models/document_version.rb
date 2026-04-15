require "stringio"

class DocumentVersion < ApplicationRecord
  TIMESTAMP_FORMAT = "%Y%m%dT%H%M%SZ".freeze

  belongs_to :document
  has_one_attached :pdf_file
  before_destroy :prevent_destroy_when_pdf_attached

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

  def pdf_signed_url(expires_in: pdf_signed_url_expires_in)
    return nil unless Rails.env.production? || Rails.env.staging?
    return nil unless pdf_file.attached?

    pdf_file.url(
      expires_in: expires_in,
      disposition: "inline",
      filename: pdf_file.blob.filename
    )
  end

  def pdf_signed_url_expires_in
    configured = Rails.application.config.x.documents_pdf_signed_url_expires_in.to_i
    configured.positive? ? configured : 900
  end

  private

  def prevent_destroy_when_pdf_attached
    return unless pdf_file.attached?

    errors.add(:base, "PDF files are immutable and cannot be deleted")
    throw :abort
  end
end
