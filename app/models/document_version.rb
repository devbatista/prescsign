class DocumentVersion < ApplicationRecord
  belongs_to :document

  validates :version_number, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 1 }
  validates :content, presence: true
  validates :checksum, length: { minimum: 16 }, allow_blank: true
end
