require "rails_helper"

RSpec.describe "CORS configuration", type: :request do
  it "allows requests from configured trusted origins" do
    get "/v1/health", headers: {
      "HOST" => "localhost",
      "Origin" => "http://localhost:5173"
    }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Access-Control-Allow-Origin"]).to eq("http://localhost:5173")
    expect(response.headers["Vary"]).to include("Origin")
  end

  it "does not allow requests from untrusted origins" do
    get "/v1/health", headers: {
      "HOST" => "localhost",
      "Origin" => "https://evil.example.com"
    }

    expect(response).to have_http_status(:ok)
    expect(response.headers["Access-Control-Allow-Origin"]).to be_nil
  end
end
