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

  describe "patient personal and health data (LGPD)" do
    let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

    it "filters the patient's identification, including the e-mail" do
      filtered = filter.filter(
        "patient" => {
          "full_name" => "Maria da Silva",
          "birth_date" => "1980-01-01",
          "email" => "maria@example.com",
          "phone" => "+5511999999999"
        },
        "recipient" => "+5511999999999"
      )

      expect(filtered["patient"].values).to all(eq("[FILTERED]"))
      expect(filtered["recipient"]).to eq("[FILTERED]")
    end

    it "filters the clinical fields of certificates and consultations" do
      filtered = filter.filter(
        # Fora de `medical_certificate`, que já cai inteiro no filtro `:certificate`
        # (pensado para o certificado digital): o CID não pode depender disso.
        "document" => { "icd_code" => "F32.1", "rest_days" => "3" },
        "consultation" => {
          "chief_complaint" => "dor torácica",
          "notes" => "histórico familiar",
          "diagnosis" => "angina",
          "status" => "finished"
        }
      )

      expect(filtered.dig("document", "icd_code")).to eq("[FILTERED]")
      expect(filtered.dig("consultation", "chief_complaint")).to eq("[FILTERED]")
      expect(filtered.dig("consultation", "notes")).to eq("[FILTERED]")
      expect(filtered.dig("consultation", "diagnosis")).to eq("[FILTERED]")
      expect(filtered.dig("document", "rest_days")).to eq("3")
      expect(filtered.dig("consultation", "status")).to eq("finished")
    end

    it "filters what was prescribed, in both nested-attributes shapes" do
      item = { "name" => "Rivotril 2mg", "active_ingredient" => "clonazepam", "posology" => "1 cp à noite" }
      filtered = filter.filter(
        "prescription" => {
          "prescription_items_attributes" => { "0" => item.dup },
          "issued_on" => "2026-10-15"
        },
        "other" => { "prescription_items_attributes" => [ item.dup ] }
      )

      from_form = filtered.dig("prescription", "prescription_items_attributes", "0")
      from_array = filtered.dig("other", "prescription_items_attributes", 0)
      expect(from_form.values).to all(eq("[FILTERED]"))
      expect(from_array.values).to all(eq("[FILTERED]"))
      expect(filtered.dig("prescription", "issued_on")).to eq("2026-10-15")
    end

    it "filters the patient search term without hiding unrelated names" do
      filtered = filter.filter("q" => "Maria", "organization" => { "name" => "Clínica Central" })

      expect(filtered["q"]).to eq("[FILTERED]")
      expect(filtered.dig("organization", "name")).to eq("Clínica Central")
    end
  end
end
