require "rails_helper"
require "securerandom"

RSpec.describe PrescriptionPolicy, type: :policy do
  describe "permissions" do
    it "allows only the owner doctor to access and edit draft prescriptions" do
      doctor = create_doctor
      other_doctor = create_doctor
      patient = create_patient
      prescription = create_prescription(doctor:, patient:, status: "draft")

      owner_policy = described_class.new(doctor, prescription)
      other_policy = described_class.new(other_doctor, prescription)

      expect(owner_policy.show?).to be(true)
      expect(owner_policy.update?).to be(true)
      expect(owner_policy.destroy?).to be(true)

      expect(other_policy.show?).to be(false)
      expect(other_policy.update?).to be(false)
      expect(other_policy.destroy?).to be(false)
    end

    it "blocks update and destroy for signed prescriptions" do
      doctor = create_doctor
      patient = create_patient
      prescription = create_prescription(doctor:, patient:, status: "signed")
      policy = described_class.new(doctor, prescription)

      expect(policy.update?).to be(false)
      expect(policy.destroy?).to be(false)
    end
  end

  describe "scope" do
    it "returns only prescriptions from the authenticated doctor" do
      doctor = create_doctor
      other_doctor = create_doctor
      patient = create_patient
      own_prescription = create_prescription(doctor:, patient:, status: "draft")
      other_prescription = create_prescription(doctor: other_doctor, patient:, status: "draft")

      scope = described_class::Scope.new(doctor, Prescription.all).resolve

      expect(scope).to include(own_prescription)
      expect(scope).not_to include(other_prescription)
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

  def create_prescription(doctor:, patient:, status:)
    suffix = SecureRandom.hex(4)
    Prescription.create!(
      doctor:,
      patient:,
      code: "RX#{suffix}AA",
      content: "Tomar 1 comprimido ao dia",
      issued_on: Date.current,
      status:
    )
  end
end
