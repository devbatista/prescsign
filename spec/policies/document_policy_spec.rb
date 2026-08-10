require "rails_helper"
require "securerandom"

RSpec.describe DocumentPolicy, type: :policy do
  describe "permissions" do
    it "allows owner updates only while document is mutable" do
      doctor = create_doctor
      patient = create_patient(doctor: doctor)
      issued_document = create_document(doctor:, patient:, status: "issued")
      sent_document = create_document(doctor:, patient:, status: "sent")

      issued_policy = described_class.new(doctor, issued_document)
      sent_policy = described_class.new(doctor, sent_document)

      expect(issued_policy.update?).to be(true)
      expect(issued_policy.destroy?).to be(true)

      expect(sent_policy.update?).to be(false)
      expect(sent_policy.destroy?).to be(false)
    end

    it "allows signing only for mutable documents owned by doctor" do
      doctor = create_doctor
      patient = create_patient(doctor: doctor)
      issued_document = create_document(doctor:, patient:, status: "issued")
      sent_document = create_document(doctor:, patient:, status: "sent")
      admin = create_user_with_role(role: "admin", organization: doctor.current_organization)

      expect(described_class.new(doctor, issued_document).sign?).to be(true)
      expect(described_class.new(doctor, sent_document).sign?).to be(false)
      expect(described_class.new(admin, issued_document).sign?).to be(false)
      expect(described_class.new(doctor, issued_document).integrity_check?).to be(true)
    end

    it "allows resend only for signed documents that are not revoked" do
      doctor = create_doctor
      patient = create_patient(doctor: doctor)
      signed_document = create_document(doctor:, patient:, status: "sent", signed_at: Time.current)
      unsigned_document = create_document(doctor:, patient:, status: "issued")
      revoked_document = create_document(doctor:, patient:, status: "revoked", signed_at: Time.current)

      expect(described_class.new(doctor, signed_document).resend?).to be(true)
      expect(described_class.new(doctor, unsigned_document).resend?).to be(false)
      expect(described_class.new(doctor, revoked_document).resend?).to be(false)
    end
  end

  describe "scope" do
    it "returns only documents owned by current doctor" do
      doctor = create_doctor
      other_doctor = create_doctor
      own_document = create_document(doctor:, patient: create_patient(doctor: doctor), status: "issued")
      other_document = create_document(doctor: other_doctor, patient: create_patient(doctor: other_doctor), status: "issued")

      scope = described_class::Scope.new(doctor, Document.all).resolve

      expect(scope).to include(own_document)
      expect(scope).not_to include(other_document)
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

  def create_user_with_role(role:, organization:)
    suffix = SecureRandom.hex(4)
    user = User.create!(
      email: "#{role}.policy.#{suffix}@example.com",
      password: "password123",
      password_confirmation: "password123",
      confirmed_at: Time.current,
      current_organization: organization
    )
    user.user_roles.create!(role: role, status: "active")
    user.organization_memberships.create!(organization: organization, role: "owner", status: "active")
    user
  end

  def create_patient(doctor:)
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    Patient.create!(
      doctor: doctor,
      full_name: "Paciente Policy #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1)
    )
  end

  def create_document(doctor:, patient:, status:, signed_at: nil)
    suffix = SecureRandom.hex(4)
    prescription = Prescription.create!(
      doctor:,
      patient:,
      code: "RX#{suffix}AA",
      content: "Uso oral",
      issued_on: Date.current,
      status: "draft"
    )

    Document.create!(
      doctor:,
      patient:,
      documentable: prescription,
      kind: "prescription",
      code: "DOC#{suffix}A",
      status:,
      issued_on: Date.current,
      current_version: 1,
      signed_at:
    )
  end
end
