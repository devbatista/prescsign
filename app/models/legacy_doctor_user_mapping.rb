class LegacyDoctorUserMapping < ApplicationRecord
  belongs_to :legacy_doctor, class_name: "Doctor"
  belongs_to :user

  validates :backfilled_at, presence: true
end
