require "rails_helper"
require "securerandom"

RSpec.describe "Rate limiting", type: :request do
  before do
    Rails.cache.clear
    Prescsign::RateLimiter.clear!
  end

  after do
    Rails.cache.clear
    Prescsign::RateLimiter.clear!
    Rails.application.config.x.rate_limits = original_rate_limits
  end

  let(:original_rate_limits) { Rails.application.config.x.rate_limits.deep_dup }

  it "throttles repeated login attempts" do
    doctor = create_confirmed_doctor
    set_limit(:auth_login, limit: 2, period: 60)

    2.times do
      post "/v1/auth/login", params: { doctor: { email: doctor.email, password: "wrong-password" } }, as: :json, headers: host_headers
      expect(response).to have_http_status(:unauthorized)
    end

    post "/v1/auth/login", params: { doctor: { email: doctor.email, password: "wrong-password" } }, as: :json, headers: host_headers

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to eq("60")
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("Rate limit exceeded. Try again later.")
    expect(body.dig("meta", "retry_after")).to eq(60)
  end

  it "throttles refresh token endpoint" do
    set_limit(:auth_refresh, limit: 1, period: 45)

    post "/v1/auth/refresh", params: { refresh_token: "invalid-token" }, as: :json, headers: host_headers
    expect(response).to have_http_status(:unauthorized)

    post "/v1/auth/refresh", params: { refresh_token: "invalid-token" }, as: :json, headers: host_headers

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to eq("45")
  end

  it "throttles public document validation endpoint" do
    set_limit(:public_document_validation, limit: 1, period: 30)

    get "/v1/public/documents/UNKNOWN-CODE/validation", headers: host_headers
    expect(response).to have_http_status(:not_found)

    get "/v1/public/documents/UNKNOWN-CODE/validation", headers: host_headers

    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to eq("30")
  end

  private

  def set_limit(name, limit:, period:)
    Rails.application.config.x.rate_limits[name] = {
      limit: limit,
      period: period
    }
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dra Rate #{suffix}",
      email: "rate.#{suffix}@example.com",
      cpf: "92345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end

  def host_headers
    { "HOST" => "localhost" }
  end
end
