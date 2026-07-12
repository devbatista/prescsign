require "rails_helper"

RSpec.describe "Request observability logging", type: :request do
  let(:organization) { create_organization }
  let(:user) { create_org_responsible(organization: organization) }

  before do
    sign_in_web(user)
    use_app_host!
  end

  it "emits a structured endpoint-monitor line with request context" do
    allow(Rails.logger).to receive(:info).and_call_original

    get "/patients"

    expect(response).to have_http_status(:ok)
    expect(Rails.logger).to have_received(:info).with(
      hash_including(
        event: "http_endpoint_monitor",
        method: "GET",
        path: "/patients",
        status_http: 200
      )
    )
  end

  it "does not raise a critical alert on a successful request" do
    expect(Observability::CriticalAlertService).not_to receive(:notify!)

    get "/patients"

    expect(response).to have_http_status(:ok)
  end
end
