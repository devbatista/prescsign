class Specialty < ApplicationRecord
  has_many :doctor_specialties, dependent: :destroy
  has_many :doctor_profiles, through: :doctor_specialties

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :active, inclusion: { in: [true, false] }

  normalizes :name, with: ->(value) { value&.strip }

  scope :active, -> { where(active: true) }

  # Case-insensitive find-or-create by name. Used by the doctor form: the user
  # picks an existing specialty or types a new one (datalist), and we resolve it
  # to a single catalog row. Retries once on a concurrent insert.
  def self.find_or_create_by_name!(raw_name)
    name = raw_name.to_s.strip
    return nil if name.blank?

    where("lower(name) = lower(?)", name).first || create!(name: name)
  rescue ActiveRecord::RecordNotUnique
    where("lower(name) = lower(?)", name).first
  end
end
