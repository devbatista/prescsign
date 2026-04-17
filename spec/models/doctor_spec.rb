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
end
