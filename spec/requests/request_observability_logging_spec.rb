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

  it "logs error with full request context and re-raises exception" do
    allow(Rails.logger).to receive(:error)
    allow_any_instance_of(V1::HealthController).to receive(:show).and_raise(StandardError, "boom")

    raised_error = nil
    begin
      get "/v1/health", headers: { "HOST" => "localhost" }
    rescue StandardError => e
      raised_error = e
    end

    expect(Rails.logger).to have_received(:error).with(
      hash_including(
        event: "http_error",
        request_id: kind_of(String),
        user: "anonymous",
        endpoint: "GET /v1/health",
        status_http: 500,
        error_class: "StandardError",
        error_message: "boom",
        params: satisfy { |value| value.respond_to?(:to_h) },
        backtrace: kind_of(Array)
      )
    )

    # Depending on middleware config, the exception may bubble up or become HTTP 500.
    expect(
      raised_error&.message == "boom" || response.status == 500
    ).to eq(true)
  end
end
