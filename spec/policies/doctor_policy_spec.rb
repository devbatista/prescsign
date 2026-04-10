require "rails_helper"
require "securerandom"

RSpec.describe DoctorPolicy, type: :policy do
  describe "permissions" do
    it "allows a doctor to access only their own profile" do
      doctor = create_doctor
      other_doctor = create_doctor

      own_policy = described_class.new(doctor, doctor)
      other_policy = described_class.new(doctor, other_doctor)

      expect(own_policy.show?).to be(true)
      expect(own_policy.update?).to be(true)
      expect(own_policy.destroy?).to be(true)

      expect(other_policy.show?).to be(false)
      expect(other_policy.update?).to be(false)
      expect(other_policy.destroy?).to be(false)
    end
  end

  describe "scope" do
    it "returns only the current doctor" do
      doctor = create_doctor
      other_doctor = create_doctor

      scope = described_class::Scope.new(doctor, Doctor.all).resolve

      expect(scope).to contain_exactly(doctor)
      expect(scope).not_to include(other_doctor)
    end
  end

  private

  def create_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    Doctor.create!(
      full_name: "Dra Policy #{suffix}",
      email: "policy.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
  end
end
