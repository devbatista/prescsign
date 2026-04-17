require "rails_helper"
require "securerandom"

RSpec.describe OrganizationPolicy, type: :policy do
  describe "scope" do
    it "returns only active organizations where doctor has active membership" do
      doctor = create_doctor

      active_member_org = Organization.create!(name: "Clinica Scope A", legal_name: "Clinica Scope A LTDA", kind: "clinica", cnpj: unique_cnpj, active: true)
      inactive_member_org = Organization.create!(name: "Clinica Scope B", legal_name: "Clinica Scope B LTDA", kind: "clinica", cnpj: unique_cnpj, active: false)
      active_non_member_org = Organization.create!(name: "Clinica Scope C", legal_name: "Clinica Scope C LTDA", kind: "clinica", cnpj: unique_cnpj, active: true)

      OrganizationMembership.create!(doctor: doctor, organization: active_member_org, role: "doctor", status: "active")
      OrganizationMembership.create!(doctor: doctor, organization: inactive_member_org, role: "doctor", status: "active")

      scope = described_class::Scope.new(doctor, Organization.all).resolve

      expect(scope).to include(active_member_org)
      expect(scope).not_to include(inactive_member_org)
      expect(scope).not_to include(active_non_member_org)
    end
  end

  describe "permissions" do
    it "allows switch/show only for organizations where doctor is a member" do
      doctor = create_doctor
      own_organization = Organization.create!(name: "Clinica Own", legal_name: "Clinica Own LTDA", kind: "clinica", cnpj: unique_cnpj, active: true)
      other_organization = Organization.create!(name: "Clinica Other", legal_name: "Clinica Other LTDA", kind: "clinica", cnpj: unique_cnpj, active: true)
      OrganizationMembership.create!(doctor: doctor, organization: own_organization, role: "doctor", status: "active")

      own_policy = described_class.new(doctor, own_organization)
      other_policy = described_class.new(doctor, other_organization)

      expect(own_policy.index?).to be(true)
      expect(own_policy.show?).to be(true)
      expect(own_policy.switch?).to be(true)

      expect(other_policy.show?).to be(false)
      expect(other_policy.switch?).to be(false)
    end
  end

  private

  def create_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    Doctor.create!(
      full_name: "Dra Org Policy #{suffix}",
      email: "org.policy.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current
    )
  end

  def unique_cnpj
    SecureRandom.random_number(10**14).to_s.rjust(14, "0")
  end
end
