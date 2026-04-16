require "rails_helper"

RSpec.describe "Request observability logging", type: :request do
  it "logs required request fields" do
    allow(Rails.logger).to receive(:info)

    get "/v1/health", headers: { "HOST" => "localhost" }

    expect(response).to have_http_status(:ok)
    expect(Rails.logger).to have_received(:info).with(
      hash_including(
        event: "http_request",
        request_id: kind_of(String),
        user: "anonymous",
        endpoint: "GET /v1/health",
        latency_ms: kind_of(Numeric),
        status_http: 200
      )
    )
  end
end
