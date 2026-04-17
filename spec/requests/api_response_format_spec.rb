require "rails_helper"

RSpec.describe "API response format", type: :request do
  it "wraps success payloads in data envelope" do
    get "/api/v1/health", headers: { "HOST" => "localhost" }

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["data"]).to eq("status" => "ok")
    expect(body["status"]).to eq("ok")
  end

  it "wraps errors in errors envelope" do
    get "/api/v1/public/documents/CODEINEXIST/validation", headers: { "HOST" => "localhost" }

    expect(response).to have_http_status(:not_found)
    body = JSON.parse(response.body)
    expect(body["errors"]).to include("Document not found")
    expect(body["error"]).to eq("Document not found")
  end
end
