class DoctorSpecialty < ApplicationRecord
  belongs_to :doctor_profile
  belongs_to :specialty

  # Virtual field for the form: the user types (or picks) a specialty name and we
  # resolve it to a catalog row via find_or_create before validation.
  attr_accessor :specialty_name

  before_validation :resolve_specialty_from_name

  validates :specialty_id, uniqueness: { scope: :doctor_profile_id }

  normalizes :rqe_number, with: ->(value) { value&.strip.presence }

  private

  def resolve_specialty_from_name
    return if specialty_name.blank?

    self.specialty = Specialty.find_or_create_by_name!(specialty_name)
  end
end
