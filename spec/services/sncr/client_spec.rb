require "rails_helper"

RSpec.describe Sncr::Client do
  let(:client) { described_class.new(base_url: "https://sncr.example/api/v1") }

  describe "#exchange_token" do
    it "mapeia a resposta de token" do
      allow(client).to receive(:get_json).and_return("access_token" => "jwt", "token_type" => "Bearer")

      token = client.exchange_token(session_id: "sess")

      expect(token.access_token).to eq("jwt")
      expect(token.token_type).to eq("Bearer")
    end

    it "assume Bearer quando token_type ausente" do
      allow(client).to receive(:get_json).and_return("access_token" => "jwt")

      expect(client.exchange_token(session_id: "sess").token_type).to eq("Bearer")
    end

    it "exige session_id" do
      expect { client.exchange_token(session_id: "") }.to raise_error(Sncr::Error, /session_id/)
    end

    it "falha quando access_token está ausente" do
      allow(client).to receive(:get_json).and_return({})

      expect { client.exchange_token(session_id: "s") }.to raise_error(Sncr::Error, /inválida/)
    end
  end

  describe "#request_notificacao!" do
    it "mapeia a lista de números (numeracoesReceita)" do
      allow(client).to receive(:post_json).and_return(
        "numeracoesReceita" => %w[2411.1-00.0000001 2411.1-00.0000002],
        "saldoReceitas" => 49,
        "mensagem" => "Saldo inferior a 50"
      )

      result = client.request_notificacao!(receita: "NRA", conselho: "CRM", uf: "RJ", documento: "123", quantidade: 10)

      expect(result.numbers).to eq(%w[2411.1-00.0000001 2411.1-00.0000002])
      expect(result.balance).to eq(49)
      expect(result.message).to eq("Saldo inferior a 50")
    end

    it "aceita a chave alternativa numeroReceita" do
      allow(client).to receive(:post_json).and_return("numeroReceita" => %w[2411.1-00.0000003])

      result = client.request_notificacao!(receita: "NRA", conselho: "CRM", uf: "RJ", documento: "1", quantidade: 10)

      expect(result.numbers).to eq(%w[2411.1-00.0000003])
    end
  end

  describe "#request_especial_retencao!" do
    it "mapeia o bloco de numeração" do
      allow(client).to receive(:post_json).and_return(
        "inicio" => "2602.6-53.0000001",
        "fim" => "2602.6-53.0001000",
        "quantidade" => 1000,
        "mensagem" => "Numeração gerada com sucesso."
      )

      result = client.request_especial_retencao!(conselho: "CRM", tipo: "RCE", documento: "1", uf: "RJ", cnpj: "11111111111111")

      expect(result.range_start).to eq("2602.6-53.0000001")
      expect(result.range_end).to eq("2602.6-53.0001000")
      expect(result.quantity).to eq(1000)
    end
  end

  describe "configuração e helpers" do
    it "falha quando a URL base não está configurada" do
      bad = described_class.new(base_url: "")

      expect {
        bad.request_notificacao!(receita: "NRA", conselho: "CRM", uf: "RJ", documento: "1", quantidade: 10)
      }.to raise_error(Sncr::Error, /URL base/)
    end

    it "monta a URI com query" do
      uri = client.send(:build_uri, "/auth/token", { session_id: "abc" })

      expect(uri.to_s).to eq("https://sncr.example/api/v1/auth/token?session_id=abc")
    end

    it "formata a mensagem de erro do SNCR" do
      response = instance_double(Net::HTTPBadRequest, code: "400", message: "Bad Request")

      message = client.send(:error_message, response, "error_message" => "Tipo de receita inválido")

      expect(message).to include("400").and include("Tipo de receita inválido")
    end
  end
end
