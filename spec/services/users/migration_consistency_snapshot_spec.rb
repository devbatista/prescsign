require "rails_helper"
require "securerandom"

RSpec.describe Users::MigrationConsistencySnapshot do
  it "returns expected consistency payload keys" do
    create_confirmed_doctor

    snapshot = described_class.call

    expect(snapshot).to include(
      :doctors_total,
      :users_total,
      :mappings_total,
      :doctor_profiles_total,
      :organization_responsibles_pending_internal_link_total,
      :missing_mapping_doctor_ids,
      :missing_doctor_profile_doctor_ids,
      :pending_internal_responsible_ids,
      :consistent
    )
    expect(snapshot[:consistent]).to be_in([true, false])
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr Snapshot #{suffix}",
      email: "snapshot.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end
end
