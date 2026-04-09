require "rails_helper"
require "securerandom"

RSpec.describe "Doctor self profile", type: :request do
  describe "GET /v1/auth/me" do
    it "returns current authenticated doctor" do
      doctor = create_confirmed_doctor
      access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)

      get "/v1/auth/me", headers: auth_headers(access_token), as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["id"]).to eq(doctor.id)
      expect(body["email"]).to eq(doctor.email)
    end

    it "returns unauthorized without token" do
      get "/v1/auth/me", headers: host_headers, as: :json

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "PATCH /v1/auth/me" do
    it "updates current doctor profile" do
      doctor = create_confirmed_doctor
      access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)

      patch "/v1/auth/me", params: {
        doctor: {
          full_name: "Dra Ana Atualizada",
          specialty: "Cardiologia"
        }
      }, headers: auth_headers(access_token), as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["full_name"]).to eq("Dra Ana Atualizada")
      expect(body["specialty"]).to eq("Cardiologia")
    end

    it "ignores blank password fields" do
      doctor = create_confirmed_doctor
      access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)
      old_encrypted_password = doctor.encrypted_password

      patch "/v1/auth/me", params: {
        doctor: {
          full_name: "Dra Ana Sem Troca de Senha",
          password: "",
          password_confirmation: ""
        }
      }, headers: auth_headers(access_token), as: :json

      expect(response).to have_http_status(:ok)
      expect(doctor.reload.encrypted_password).to eq(old_encrypted_password)
    end
  end

  describe "DELETE /v1/auth/me" do
    it "deactivates current doctor" do
      doctor = create_confirmed_doctor
      access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)

      delete "/v1/auth/me", headers: auth_headers(access_token), as: :json

      expect(response).to have_http_status(:no_content)
      expect(doctor.reload.active).to be(false)
    end
  end

  private

  def auth_headers(token)
    host_headers.merge("Authorization" => "Bearer #{token}")
  end

  def host_headers
    { "HOST" => "localhost" }
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dra Ana Lima #{suffix}",
      email: "ana.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end
end
