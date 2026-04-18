require "rails_helper"
require "securerandom"

RSpec.describe Users::BackfillFromDoctors do
  it "backfills doctors into users, roles, profiles, mappings and internal responsibles" do
    doctor = create_confirmed_doctor
    organization = create_organization
    responsible = OrganizationResponsible.create!(organization: organization, doctor: doctor, user: nil)
    expected_processed = Doctor.count

    report = described_class.new.call

    mapping = LegacyDoctorUserMapping.find_by(legacy_doctor_id: doctor.id)
    expect(mapping).to be_present

    user = mapping.user
    expect(user.email).to eq(doctor.email.downcase)
    expect(user.user_roles.where(role: "doctor", status: "active")).to exist

    profile = DoctorProfile.find_by(user_id: user.id)
    expect(profile).to be_present
    expect(profile.doctor_id).to eq(doctor.id)
    expect(profile.cpf).to eq(doctor.cpf)

    responsible.reload
    expect(responsible.user_id).to eq(user.id)

    expect(report.processed_doctors).to eq(expected_processed)
    expect(report.created_users).to be >= 1
    expect(report.created_profiles).to be >= 1
    expect(report.mapped_doctors).to eq(expected_processed)
    expect(report.updated_organization_responsibles).to be >= 1
    expect(report.divergences).to eq([])
    expect(report.consistency[:consistent]).to be(true)
  end

  it "is idempotent when executed multiple times" do
    doctor = create_confirmed_doctor

    first_report = described_class.new.call
    second_report = described_class.new.call
    expected_processed = Doctor.count

    mapping = LegacyDoctorUserMapping.find_by!(legacy_doctor_id: doctor.id)
    expect(User.where(email: doctor.email.downcase).count).to eq(1)
    expect(DoctorProfile.where(user_id: mapping.user_id).count).to eq(1)
    expect(UserRole.where(user_id: mapping.user_id, role: "doctor").count).to eq(1)
    expect(LegacyDoctorUserMapping.where(legacy_doctor_id: doctor.id).count).to eq(1)

    expect(first_report.consistency[:consistent]).to be(true)
    expect(second_report.consistency[:consistent]).to be(true)
    expect(second_report.created_users).to eq(0)
    expect(second_report.reused_users).to eq(expected_processed)
    expect(second_report.created_profiles).to eq(0)
    expect(second_report.updated_profiles).to eq(expected_processed)
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dr Backfill #{suffix}",
      email: "backfill.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end

  def create_organization
    Organization.create!(
      name: "Backfill Org #{SecureRandom.hex(4)}",
      kind: "autonomo"
    )
  end
end
