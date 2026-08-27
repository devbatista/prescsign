require "rails_helper"
require "base64"
require "json"

RSpec.describe Sncr::FakeClient do
  include WebSpecHelpers

  let(:organization) { create_organization }
  let(:user) do
    u = create_user(organization: organization)
    create_membership(user: u, organization: organization, role: "doctor")
    create_doctor_profile(user: u)
    u.reload
  end
  let(:profile) { user.doctor_profile }
  let(:client) { described_class.new }

  def notificacao(sncr_type: "NRB", quantidade: 3, documento: "CRM12345")
    client.request_notificacao!(
      receita: sncr_type, conselho: "CRM", uf: "SP", documento: documento, quantidade: quantidade
    )
  end

  describe "#request_notificacao!" do
    it "gera a quantidade pedida no formato nacional aceito pelo pool" do
      result = notificacao(quantidade: 3)

      expect(result.numbers.size).to eq(3)
      expect(result.numbers).to all(match(SncrNumbering::NUMBER_FORMAT))
    end

    it "continua a sequência entre lotes, sem repetir números já no pool" do
      first = notificacao(quantidade: 2)
      SncrNumbering.import_numbers!(doctor_profile: profile, sncr_type: "NRB", numbers: first.numbers)

      second = notificacao(quantidade: 2)

      expect(second.numbers & first.numbers).to be_empty
      expect(second.numbers.first).to eq(first.numbers.last.succ)
    end

    it "separa as séries por tipo de receita" do
      nrb = notificacao(sncr_type: "NRB", quantidade: 1).numbers.first
      nra = notificacao(sncr_type: "NRA", quantidade: 1).numbers.first

      expect(SncrNumbering.split_number(nrb).first).not_to eq(SncrNumbering.split_number(nra).first)
    end

    it "recusa um tipo que pertence ao outro endpoint" do
      expect { notificacao(sncr_type: "RCE") }
        .to raise_error(Sncr::Error, /Valores permitidos/)
    end

    it "recusa quantidade acima do limite de 50 por solicitação" do
      expect { notificacao(quantidade: 51) }.to raise_error(Sncr::Error, /Quantidade/)
    end

    it "recusa campo obrigatório em branco, como a API real" do
      expect { notificacao(documento: "") }.to raise_error(Sncr::Error, /Documento não pode ser nulo/)
    end

    it "avisa quando o saldo mensal simulado fica abaixo de 50" do
      allow(client).to receive(:issued_this_month).and_return(described_class::MONTHLY_LIMIT - 60)

      expect(notificacao(quantidade: 20).message).to match(/Saldo inferior a 50/)
    end

    it "recusa o lote que estoura o limite mensal de 3.000 por tipo" do
      allow(client).to receive(:issued_this_month).and_return(described_class::MONTHLY_LIMIT)

      expect { notificacao(quantidade: 1) }.to raise_error(Sncr::Error, /limite máximo/)
    end
  end

  describe "#request_especial_retencao!" do
    it "devolve um bloco contínuo de 1.000 números" do
      result = client.request_especial_retencao!(
        conselho: "CRM", tipo: "RCE", documento: "CRM12345", uf: "SP", cnpj: "12345678000199"
      )

      expect(result.quantity).to eq(1_000)
      expect(SncrNumbering.expand_range(result.range_start, result.range_end).size).to eq(1_000)
    end

    it "recusa um tipo de Notificação de Receita" do
      expect do
        client.request_especial_retencao!(
          conselho: "CRM", tipo: "NRB", documento: "CRM12345", uf: "SP", cnpj: "12345678000199"
        )
      end.to raise_error(Sncr::Error, /Valores permitidos/)
    end
  end

  describe "#exchange_token" do
    it "emite um JWT sintético com exp futuro, legível pelo TokenStore" do
      token = client.exchange_token(session_id: "fake-session")
      payload = token.access_token.split(".")[1]
      claims = JSON.parse(Base64.urlsafe_decode64(payload + ("=" * ((4 - payload.length % 4) % 4))))

      expect(token.token_type).to eq("Bearer")
      expect(claims["exp"]).to be > Time.current.to_i
    end

    it "exige session_id, como o cliente real" do
      expect { client.exchange_token(session_id: "") }.to raise_error(Sncr::Error, /session_id/)
    end
  end
end
