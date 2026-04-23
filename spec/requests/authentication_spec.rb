require "rails_helper"
require "securerandom"

RSpec.describe "Authentication", type: :request do
  describe "POST /v1/auth/register" do
    it "registers a doctor and sends confirmation instructions" do
      attrs = doctor_params

      post "/v1/auth/register", params: { doctor: attrs }, as: :json, headers: host_headers

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["message"]).to eq("Registration successful. Please confirm your email.")
      expect(body.dig("doctor", "email")).to eq(attrs[:email])
      expect(body.dig("doctor", "cpf")).to be_nil
      expect(body.dig("doctor", "cpf_masked")).to match(/\A\*\*\*\.\*\*\*\.\*\*\*-\d{2}\z/)
      expect(body.dig("doctor", "current_organization_id")).to be_present
      expect(body.dig("doctor", "role")).to eq("owner")
      expect(body.dig("doctor", "professional_title")).to eq("Dra.")
      expect(body.dig("doctor", "welcome_prefix")).to eq("Bem-vinda")
      doctor = Doctor.find_by(email: attrs[:email])
      expect(doctor).to be_present
      expect(doctor.current_organization_id).to be_present
      expect(doctor.active_organization_memberships).to exist
      user = User.find_by(email: attrs[:email].downcase)
      expect(user).to be_present
      expect(user).not_to be_confirmed
      expect(user.confirmation_token).to be_present
      expect(user.confirmation_sent_at).to be_present
    end

    it "sends a confirmation token by email" do
      post "/v1/auth/register", params: { doctor: doctor_params }, as: :json, headers: host_headers

      user = User.order(:created_at).last
      expect(user).to be_present
      expect(user.confirmation_token).to be_present
    end

    it "rolls back doctor creation when confirmation delivery fails" do
      attrs = doctor_params
      allow_any_instance_of(User).to receive(:send_confirmation_instructions).and_raise(StandardError, "mail failure")

      expect {
        post "/v1/auth/register", params: { doctor: attrs }, as: :json, headers: host_headers
      }.not_to change(Doctor, :count)

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body["error"]).to eq("Could not complete registration")
    end
  end

  describe "GET /v1/auth/confirmation" do
    it "confirms account with valid token" do
      post "/v1/auth/register", params: { doctor: doctor_params }, as: :json, headers: host_headers
      token = User.order(:created_at).last.confirmation_token.to_s

      get "/v1/auth/confirmation", params: { confirmation_token: token }, headers: host_headers

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["message"]).to eq("Email confirmed successfully")
      expect(User.order(:created_at).last).to be_confirmed
    end
  end

  describe "POST /v1/auth/login" do
    it "authenticates and returns access and refresh tokens" do
      doctor = create_confirmed_doctor

      post "/v1/auth/login", params: {
        doctor: { email: doctor.email, password: "password123" }
      }, as: :json, headers: host_headers

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["access_token"]).to be_present
      expect(body["refresh_token"]).to be_present
      expect(body["user"]).to be_present
      expect(body.dig("user", "email")).to eq(doctor.email.downcase)
      expect(body.dig("user", "roles")).to include("doctor")
      expect(body.dig("doctor", "cpf")).to be_nil
      expect(body.dig("doctor", "cpf_masked")).to match(/\A\*\*\*\.\*\*\*\.\*\*\*-\d{2}\z/)
      expect(body.dig("doctor", "role")).to be_present
      expect(body.dig("doctor", "professional_title")).to eq("Dra.")
      expect(body.dig("doctor", "welcome_prefix")).to eq("Bem-vinda")
    end

    it "rejects invalid credentials" do
      doctor = create_confirmed_doctor

      post "/v1/auth/login", params: {
        doctor: { email: doctor.email, password: "wrong-password" }
      }, as: :json, headers: host_headers

      expect(response).to have_http_status(:unauthorized)
    end

    it "rejects unconfirmed accounts" do
      doctor = Doctor.create!(doctor_params)

      post "/v1/auth/login", params: {
        doctor: { email: doctor.email, password: "password123" }
      }, as: :json, headers: host_headers

      expect(response).to have_http_status(:unauthorized)
      expect(JSON.parse(response.body)["error"]).to eq("Please confirm your email before logging in")
    end
  end

  describe "POST /v1/auth/refresh" do
    it "rotates refresh token and emits new access token" do
      doctor = create_confirmed_doctor

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
      expect(second_tokens["user"]).to be_present
      expect(second_tokens.dig("user", "roles")).to include("doctor")
      expect(second_tokens.dig("doctor", "cpf")).to be_nil
      expect(second_tokens.dig("doctor", "cpf_masked")).to match(/\A\*\*\*\.\*\*\*\.\*\*\*-\d{2}\z/)
      expect(second_tokens.dig("doctor", "role")).to be_present
      expect(second_tokens.dig("doctor", "professional_title")).to eq("Dra.")
      expect(second_tokens.dig("doctor", "welcome_prefix")).to eq("Bem-vinda")

      post "/v1/auth/refresh", params: { refresh_token: first_refresh }, as: :json, headers: host_headers
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "DELETE /v1/auth/logout" do
    it "revokes access token and active refresh tokens" do
      doctor = create_confirmed_doctor
      access_token, payload = Warden::JWTAuth::UserEncoder.new.call(doctor.user, :user, nil)
      user = Auth::UserIdentityResolver.resolve_for_doctor(doctor)
      refresh_token = Auth::RefreshTokenService.issue_for(user: user, doctor: doctor)

      delete "/v1/auth/logout", headers: host_headers.merge("Authorization" => "Bearer #{access_token}"), as: :json

      expect(response).to have_http_status(:no_content)
      expect(JwtDenylist.find_by(jti: payload["jti"])).to be_present
      expect(Auth::RefreshTokenService.find_active(refresh_token)).to be_nil
    end
  end

  describe "POST /v1/auth/password and PUT /v1/auth/password" do
    it "requests reset and updates password with valid token" do
      doctor = create_confirmed_doctor

      post "/v1/auth/password", params: { doctor: { email: doctor.email } }, as: :json, headers: host_headers
      expect(response).to have_http_status(:ok)

      raw_reset_token = doctor.user.send(:set_reset_password_token)

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

  def create_confirmed_doctor
    doctor = Doctor.create!(doctor_params)
    doctor.confirm
    doctor
  end

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
