require "rails_helper"
require "securerandom"

RSpec.describe Doctor, type: :model do
  describe "#masked_cpf" do
    it "returns masked cpf with only last two digits visible" do
      suffix = SecureRandom.hex(4)
      cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
      doctor = Doctor.new(
        full_name: "Dra Mask #{suffix}",
        email: "mask.#{suffix}@example.com",
        cpf: "12345#{cpf_suffix}",
        license_number: "CRM#{suffix}",
        license_state: "SP",
        password: "password123",
        password_confirmation: "password123"
      )

      expect(doctor.masked_cpf).to match(/\A\*\*\*\.\*\*\*\.\*\*\*-\d{2}\z/)
      expect(doctor.masked_cpf).to end_with(doctor.cpf.to_s[-2, 2])
    end
  end

  describe "#confirm" do
    it "raises when users are required and identity cannot be resolved" do
      doctor = create_doctor
      original_required = Rails.application.config.x.auth.users_required
      original_phase = Rails.application.config.x.users_migration.phase
      Rails.application.config.x.auth.users_required = true
      Rails.application.config.x.users_migration.phase = "phase3_users_required"
      allow(Auth::UserIdentityResolver).to receive(:resolve_for_doctor).and_return(nil)
      allow(doctor).to receive(:user).and_return(nil)

      expect { doctor.confirm }.to raise_error(ActiveRecord::RecordInvalid)
    ensure
      Rails.application.config.x.auth.users_required = original_required
      Rails.application.config.x.users_migration.phase = original_phase
    end
  end

  def create_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    Doctor.create!(
      full_name: "Dra Model #{suffix}",
      email: "doctor.model.#{suffix}@example.com",
      cpf: "22345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
  end
end
