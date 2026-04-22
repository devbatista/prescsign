require "rails_helper"
require "securerandom"

RSpec.describe DoctorProfilePolicy, type: :policy do
  describe "permissions" do
    it "allows user to access only their own profile" do
      own_user = create_user_with_profile
      other_user = create_user_with_profile

      own_policy = described_class.new(own_user, own_user.doctor_profile)
      other_policy = described_class.new(own_user, other_user.doctor_profile)

      expect(own_policy.show?).to be(true)
      expect(own_policy.update?).to be(true)
      expect(own_policy.destroy?).to be(true)

      expect(other_policy.show?).to be(false)
      expect(other_policy.update?).to be(false)
      expect(other_policy.destroy?).to be(false)
    end
  end

  describe "scope" do
    it "returns only current user's profile" do
      own_user = create_user_with_profile
      other_user = create_user_with_profile

      scope = described_class::Scope.new(own_user, DoctorProfile.all).resolve

      expect(scope).to contain_exactly(own_user.doctor_profile)
      expect(scope).not_to include(other_user.doctor_profile)
    end
  end

  private

  def create_user_with_profile
    suffix = SecureRandom.hex(4)
    user = User.create!(
      email: "doctor.profile.policy.#{suffix}@example.com",
      encrypted_password: "encrypted-token",
      status: "active"
    )

    DoctorProfile.create!(
      user: user,
      full_name: "Dra Policy #{suffix}",
      email: user.email,
      cpf: "12345#{suffix.hex.to_s.rjust(6, "0")[0, 6]}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      specialty: "Clinica Geral",
      active: true
    )

    user.reload
  end
end
