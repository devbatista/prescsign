require "rails_helper"
require "securerandom"

RSpec.describe PatientPolicy, type: :policy do
  describe "scope" do
    it "returns only patients linked to the authenticated doctor" do
      doctor = create_doctor
      other_doctor = create_doctor

      linked_patient = create_patient
      unlinked_patient = create_patient

      create_prescription(doctor:, patient: linked_patient, status: "draft")
      create_prescription(doctor: other_doctor, patient: unlinked_patient, status: "draft")

      scope = described_class::Scope.new(doctor, Patient.all).resolve

      expect(scope).to include(linked_patient)
      expect(scope).not_to include(unlinked_patient)
    end
  end

  describe "permissions" do
    it "allows access only when patient is linked to the authenticated doctor" do
      doctor = create_doctor
      other_doctor = create_doctor
      linked_patient = create_patient
      unlinked_patient = create_patient

      create_prescription(doctor:, patient: linked_patient, status: "draft")
      create_prescription(doctor: other_doctor, patient: unlinked_patient, status: "draft")

      linked_policy = described_class.new(doctor, linked_patient)
      unlinked_policy = described_class.new(doctor, unlinked_patient)

      expect(linked_policy.show?).to be(true)
      expect(linked_policy.update?).to be(true)
      expect(unlinked_policy.show?).to be(false)
      expect(unlinked_policy.update?).to be(false)
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
