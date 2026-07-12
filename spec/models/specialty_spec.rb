require "rails_helper"

RSpec.describe Specialty, type: :model do
  describe ".find_or_create_by_name!" do
    it "creates a normalized specialty" do
      specialty = described_class.find_or_create_by_name!("  Cardiologia  ")
      expect(specialty).to be_persisted
      expect(specialty.name).to eq("Cardiologia")
    end

    it "reuses an existing specialty case-insensitively" do
      existing = described_class.create!(name: "Cardiologia")
      expect {
        found = described_class.find_or_create_by_name!("cardiologia")
        expect(found).to eq(existing)
      }.not_to change(described_class, :count)
    end

    it "returns nil for a blank name" do
      expect(described_class.find_or_create_by_name!("   ")).to be_nil
    end
  end

  it "rejects a duplicate name (case-insensitive)" do
    described_class.create!(name: "Cardiologia")
    dup = described_class.new(name: "cardiologia")
    expect(dup).not_to be_valid
  end

  describe "N:N with doctor profiles" do
    it "links a doctor to multiple specialties" do
      user = User.create!(
        email: "spec-#{SecureRandom.hex(4)}@example.com",
        password: "password123", password_confirmation: "password123",
        status: "active", confirmed_at: Time.current
      )
      profile = DoctorProfile.create!(
        user: user, full_name: "Dra Teste", email: user.email,
        license_number: "CRM1", license_state: "SP", active: true
      )
      profile.doctor_specialties.create!(specialty: described_class.find_or_create_by_name!("Cardiologia"), rqe_number: "RQE-1")
      profile.doctor_specialties.create!(specialty: described_class.find_or_create_by_name!("Clínica Médica"))

      expect(profile.reload.specialty_names).to contain_exactly("Cardiologia", "Clínica Médica")
      expect(profile.specialty_label).to include("Cardiologia").and include("Clínica Médica")
    end
  end
end
