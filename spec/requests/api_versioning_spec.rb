require "rails_helper"

RSpec.describe "API versioning", type: :request do
  it "exposes health endpoint under /api/v1" do
    get "/api/v1/health", headers: { "HOST" => "localhost" }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("status" => "ok")
  end

  it "keeps legacy /v1 path working for backward compatibility" do
    get "/v1/health", headers: { "HOST" => "localhost" }

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq("status" => "ok")
  end
end
