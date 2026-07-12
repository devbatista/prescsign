require "rails_helper"

RSpec.describe "Auth rate limiting (rack-attack)", type: :request do
  before { use_login_host! }

  it "throttles repeated login attempts from the same IP" do
    10.times do
      post "/sign-in", params: { user: { email: "attacker@example.com", password: "wrong" } }
      expect(response).not_to have_http_status(:too_many_requests)
    end

    post "/sign-in", params: { user: { email: "attacker@example.com", password: "wrong" } }
    expect(response).to have_http_status(:too_many_requests)
    expect(response.headers["Retry-After"]).to be_present
    expect(response.body).to include("Muitas tentativas")
  end

  it "does not throttle a normal number of login attempts" do
    3.times { post "/sign-in", params: { user: { email: "user@example.com", password: "wrong" } } }
    expect(response).not_to have_http_status(:too_many_requests)
  end

  it "throttles repeated password-recovery requests from the same IP" do
    5.times { post "/forgot-password", params: { user: { email: "user@example.com" } } }
    post "/forgot-password", params: { user: { email: "user@example.com" } }
    expect(response).to have_http_status(:too_many_requests)
  end
end
