require "rails_helper"
require "securerandom"

RSpec.describe "Authentication", type: :request do
  describe "POST /v1/auth/register" do
    it "registers a doctor and returns access and refresh tokens" do
      attrs = doctor_params

      post "/v1/auth/register", params: { doctor: attrs }, as: :json, headers: host_headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["access_token"]).to be_present
      expect(body["refresh_token"]).to be_present
      expect(body.dig("doctor", "email")).to eq(attrs[:email])
    end

    it "emits jwt with 24h expiration" do
      post "/v1/auth/register", params: { doctor: doctor_params }, as: :json, headers: host_headers

      body = JSON.parse(response.body)
      payload = Warden::JWTAuth::TokenDecoder.new.call(body["access_token"])
      expect(payload["exp"]).to be_within(5).of(24.hours.from_now.to_i)
    end
  end

  describe "POST /v1/auth/login" do
    it "authenticates and returns access and refresh tokens" do
      doctor = Doctor.create!(doctor_params)

      post "/v1/auth/login", params: {
        doctor: { email: doctor.email, password: "password123" }
      }, as: :json, headers: host_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["access_token"]).to be_present
      expect(body["refresh_token"]).to be_present
    end

    it "rejects invalid credentials" do
      doctor = Doctor.create!(doctor_params)

      post "/v1/auth/login", params: {
        doctor: { email: doctor.email, password: "wrong-password" }
      }, as: :json, headers: host_headers

      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "POST /v1/auth/refresh" do
    it "rotates refresh token and emits new access token" do
      doctor = Doctor.create!(doctor_params)

      post "/v1/auth/login", params: {
        doctor: { email: doctor.email, password: "password123" }
      }, as: :json, headers: host_headers

      first_tokens = JSON.parse(response.body)
      first_refresh = first_tokens.fetch("refresh_token")

      post "/v1/auth/refresh", params: { refresh_token: first_refresh }, as: :json, headers: host_headers

      expect(response).to have_http_status(:ok)
      second_tokens = JSON.parse(response.body)
      expect(second_tokens["access_token"]).to be_present
      expect(second_tokens["refresh_token"]).to be_present
      expect(second_tokens["refresh_token"]).not_to eq(first_refresh)

      post "/v1/auth/refresh", params: { refresh_token: first_refresh }, as: :json, headers: host_headers
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /v1/auth/logout" do
    it "revokes access token and active refresh tokens" do
      doctor = Doctor.create!(doctor_params)
      access_token, payload = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)
      refresh_token = Auth::RefreshTokenService.issue_for(doctor)

      delete "/v1/auth/logout", headers: host_headers.merge("Authorization" => "Bearer #{access_token}"), as: :json

      expect(response).to have_http_status(:no_content)
      expect(JwtDenylist.find_by(jti: payload["jti"])).to be_present
      expect(Auth::RefreshTokenService.find_active(refresh_token)).to be_nil
    end
  end

  describe "POST /v1/auth/password and PUT /v1/auth/password" do
    it "requests reset and updates password with valid token" do
      doctor = Doctor.create!(doctor_params)

      post "/v1/auth/password", params: { doctor: { email: doctor.email } }, as: :json, headers: host_headers
      expect(response).to have_http_status(:ok)

      raw_reset_token = doctor.send(:set_reset_password_token)

      put "/v1/auth/password", params: {
        doctor: {
          reset_password_token: raw_reset_token,
          password: "newpassword123",
          password_confirmation: "newpassword123"
        }
      }, as: :json, headers: host_headers

      expect(response).to have_http_status(:ok)

      post "/v1/auth/login", params: {
        doctor: { email: doctor.email, password: "newpassword123" }
      }, as: :json, headers: host_headers
      expect(response).to have_http_status(:ok)
    end
  end

  private

  def host_headers
    { "HOST" => "localhost" }
  end

  def doctor_params
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    {
      full_name: "Dra Ana Lima #{suffix}",
      email: "ana.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    }
  end
end
