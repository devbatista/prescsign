class User < ApplicationRecord
  STATUSES = %w[active inactive blocked].freeze

  has_many :user_roles, dependent: :delete_all
  has_one :doctor_profile, dependent: :destroy
  has_many :legacy_doctor_user_mappings, dependent: :delete_all
  has_many :organization_responsibles, dependent: :nullify

  validates :email, presence: true, uniqueness: { case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }

  normalizes :email, with: ->(value) { value&.strip&.downcase }
  normalizes :status, with: ->(value) { value&.strip&.downcase }
end
