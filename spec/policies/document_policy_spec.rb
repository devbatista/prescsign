require "rails_helper"
require "securerandom"

RSpec.describe DocumentPolicy, type: :policy do
  describe "permissions" do
    it "allows owner updates only while document is mutable" do
      doctor = create_doctor
      patient = create_patient
      issued_document = create_document(doctor:, patient:, status: "issued")
      sent_document = create_document(doctor:, patient:, status: "sent")

      issued_policy = described_class.new(doctor, issued_document)
      sent_policy = described_class.new(doctor, sent_document)

      expect(issued_policy.update?).to be(true)
      expect(issued_policy.destroy?).to be(true)

      expect(sent_policy.update?).to be(false)
      expect(sent_policy.destroy?).to be(false)
    end
  end

  describe "scope" do
    it "returns only documents owned by current doctor" do
      doctor = create_doctor
      other_doctor = create_doctor
      patient = create_patient
      own_document = create_document(doctor:, patient:, status: "issued")
      other_document = create_document(doctor: other_doctor, patient:, status: "issued")

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

  def create_patient
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    Patient.create!(
      full_name: "Paciente Policy #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1)
    )
  end

  def create_document(doctor:, patient:, status:)
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
      current_version: 1
    )
  end
end
