require "rails_helper"
require "securerandom"

RSpec.describe ConsultationPolicy, type: :policy do
  describe "permissions" do
    it "allows doctor to read and update consultations in the same organization" do
      organization = create_organization
      doctor = create_user(current_organization: organization)
      create_membership(user: doctor, organization: organization, role: "doctor")
      consultation = create_consultation(user: doctor, organization: organization)

      policy = described_class.new(doctor, consultation)

      expect(policy.show?).to be(true)
      expect(policy.create?).to be(true)
      expect(policy.update?).to be(true)
      expect(policy.destroy?).to be(true)
    end

    it "blocks support from write actions while allowing read" do
      organization = create_organization
      support_user = create_user(current_organization: organization)
      create_membership(user: support_user, organization: organization, role: "staff")
      create_user_role(user: support_user, role: "support")
      consultation = create_consultation(user: support_user, organization: organization)

      policy = described_class.new(support_user, consultation)

      expect(policy.show?).to be(true)
      expect(policy.create?).to be(false)
      expect(policy.update?).to be(false)
      expect(policy.destroy?).to be(false)
    end

    it "blocks non-member user from same record access" do
      organization = create_organization
      member_user = create_user(current_organization: organization)
      create_membership(user: member_user, organization: organization, role: "doctor")
      consultation = create_consultation(user: member_user, organization: organization)

      outsider = create_user(current_organization: organization)
      policy = described_class.new(outsider, consultation)

      expect(policy.show?).to be(false)
      expect(policy.create?).to be(false)
      expect(policy.update?).to be(false)
      expect(policy.destroy?).to be(false)
    end
  end

  describe "scope" do
    it "returns all records for admin" do
      org_a = create_organization
      org_b = create_organization
      owner_a = create_user(current_organization: org_a)
      owner_b = create_user(current_organization: org_b)
      create_membership(user: owner_a, organization: org_a, role: "doctor")
      create_membership(user: owner_b, organization: org_b, role: "doctor")
      consultation_a = create_consultation(user: owner_a, organization: org_a)
      consultation_b = create_consultation(user: owner_b, organization: org_b)

      admin = create_user(current_organization: org_a)
      create_user_role(user: admin, role: "admin")

      scope = described_class::Scope.new(admin, Consultation.all).resolve
      expect(scope).to include(consultation_a, consultation_b)
    end

    it "returns only tenant records for support" do
      org_a = create_organization
      org_b = create_organization
      owner_a = create_user(current_organization: org_a)
      owner_b = create_user(current_organization: org_b)
      create_membership(user: owner_a, organization: org_a, role: "doctor")
      create_membership(user: owner_b, organization: org_b, role: "doctor")
      consultation_a = create_consultation(user: owner_a, organization: org_a)
      consultation_b = create_consultation(user: owner_b, organization: org_b)

      support_user = create_user(current_organization: org_a)
      create_membership(user: support_user, organization: org_a, role: "staff")
      create_user_role(user: support_user, role: "support")

      scope = described_class::Scope.new(support_user, Consultation.all).resolve
      expect(scope).to include(consultation_a)
      expect(scope).not_to include(consultation_b)
    end

    it "returns only tenant records for doctor member" do
      org_a = create_organization
      org_b = create_organization
      owner_a = create_user(current_organization: org_a)
      owner_b = create_user(current_organization: org_b)
      create_membership(user: owner_a, organization: org_a, role: "doctor")
      create_membership(user: owner_b, organization: org_b, role: "doctor")
      consultation_a = create_consultation(user: owner_a, organization: org_a)
      consultation_b = create_consultation(user: owner_b, organization: org_b)

      doctor = create_user(current_organization: org_a)
      create_membership(user: doctor, organization: org_a, role: "doctor")

      scope = described_class::Scope.new(doctor, Consultation.all).resolve
      expect(scope).to include(consultation_a)
      expect(scope).not_to include(consultation_b)
    end
  end

  private

  def create_organization
    suffix = SecureRandom.hex(4)
    Organization.create!(
      name: "Org Policy Consultation #{suffix}",
      kind: "autonomo"
    )
  end

  def create_user(current_organization:)
    suffix = SecureRandom.hex(4)
    User.create!(
      email: "consultation.policy.#{suffix}@example.com",
      encrypted_password: "encrypted-token",
      status: "active",
      current_organization: current_organization
    )
  end

  def create_membership(user:, organization:, role:)
    OrganizationMembership.create!(
      user: user,
      organization: organization,
      role: role,
      status: "active"
    )
  end

  def create_user_role(user:, role:)
    UserRole.create!(user: user, role: role, status: "active")
  end

  def create_patient(user:, organization:)
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    Patient.create!(
      user: user,
      organization: organization,
      full_name: "Paciente Policy Consultation #{suffix}",
      cpf: "98765#{cpf_suffix}",
      birth_date: Date.new(1992, 2, 2)
    )
  end

  def create_consultation(user:, organization:)
    patient = create_patient(user: user, organization: organization)

    Consultation.create!(
      user: user,
      patient: patient,
      organization: organization,
      scheduled_at: Time.current,
      status: "scheduled"
    )
  end
end
