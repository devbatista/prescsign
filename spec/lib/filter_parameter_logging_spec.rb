require "rails_helper"

RSpec.describe "Filter parameter logging configuration" do
  it "filters sensitive values such as password, cpf and signature payloads" do
    filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
    filtered = filter.filter(
      "doctor" => {
        "email" => "medico@example.com",
        "password" => "super-secret",
        "cpf" => "12345678901"
      },
      "cnpj" => "12345678000199",
      "pin" => "123456",
      "content" => "JVBERi0x",
      "pdf_base64" => "JVBERi0x"
    )

    expect(filtered.dig("doctor", "password")).to eq("[FILTERED]")
    expect(filtered.dig("doctor", "cpf")).to eq("[FILTERED]")
    expect(filtered["cnpj"]).to eq("[FILTERED]")
    expect(filtered["pin"]).to eq("[FILTERED]")
    expect(filtered["content"]).to eq("[FILTERED]")
    expect(filtered["pdf_base64"]).to eq("[FILTERED]")
    expect(filtered.dig("doctor", "email")).to eq("medico@example.com")
  end
end
