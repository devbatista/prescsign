require "rails_helper"
require "securerandom"

RSpec.describe PatientPolicy, type: :policy do
  describe "scope" do
    it "returns only patients owned by the authenticated doctor" do
      doctor = create_doctor
      other_doctor = create_doctor

      own_patient = create_patient(doctor: doctor)
      other_patient = create_patient(doctor: other_doctor)

      scope = described_class::Scope.new(doctor, Patient.all).resolve

      expect(scope).to include(own_patient)
      expect(scope).not_to include(other_patient)
    end
  end

  describe "permissions" do
    it "allows access only to owned patients" do
      doctor = create_doctor
      other_doctor = create_doctor
      own_patient = create_patient(doctor: doctor)
      other_patient = create_patient(doctor: other_doctor)

      own_policy = described_class.new(doctor, own_patient)
      other_policy = described_class.new(doctor, other_patient)

      expect(own_policy.show?).to be(true)
      expect(own_policy.update?).to be(true)
      expect(own_policy.destroy?).to be(true)

      expect(other_policy.show?).to be(false)
      expect(other_policy.update?).to be(false)
      expect(other_policy.destroy?).to be(false)
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
end
