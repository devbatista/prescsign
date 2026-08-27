require "rails_helper"

RSpec.describe Sncr::Authentication do
  describe "#login_url" do
    it "monta a URL de login com client_url e state" do
      auth = described_class.new(
        base_url: "https://sncr.example/api/v1",
        client_url: "https://app.exemplo.com.br"
      )

      url = auth.login_url(state: "/sncr")

      expect(url).to start_with("https://sncr.example/api/v1/auth/login?")
      expect(url).to include("client_url=https%3A%2F%2Fapp.exemplo.com.br")
      expect(url).to include("state=%2Fsncr")
    end

    # A Anvisa lê o último segmento depois da última "/" e exige que termine em
    # `.br`; qualquer path derruba o fluxo com 403. Ver docs/sncr 4.2.1.
    it "descarta o path do client_url e envia só a origem" do
      auth = described_class.new(
        base_url: "https://sncr.example",
        client_url: "https://app.exemplo.com.br/sncr/auth/callback"
      )

      expect(auth.login_url).to include("client_url=https%3A%2F%2Fapp.exemplo.com.br")
      expect(auth.login_url).not_to include("callback")
    end

    it "recusa client_url fora de um domínio .br, que a Anvisa rejeitaria com 403" do
      auth = described_class.new(
        base_url: "https://sncr.example",
        client_url: "http://app.prescsign.local:8080/sncr/auth/callback"
      )

      expect { auth.login_url }
        .to raise_error(Sncr::Error, /só aceita client_url de domínio \.br/)
    end

    it "recusa client_url sem host" do
      auth = described_class.new(base_url: "https://sncr.example", client_url: "app.exemplo.com.br")

      expect { auth.login_url }.to raise_error(Sncr::Error, /inválido/)
    end

    it "omite o state quando ausente" do
      auth = described_class.new(base_url: "https://sncr.example", client_url: "https://app.exemplo.com.br")

      expect(auth.login_url).not_to include("state=")
    end

    it "exige a URL base" do
      expect { described_class.new(base_url: "", client_url: "x").login_url }
        .to raise_error(Sncr::Error, /URL base/)
    end

    it "exige o client_url" do
      expect { described_class.new(base_url: "x", client_url: "").login_url }
        .to raise_error(Sncr::Error, /client_url/)
    end
  end

  describe "#exchange_session!" do
    it "delega a troca de token ao client" do
      token = Sncr::Client::Token.new(access_token: "jwt", token_type: "Bearer")
      client = instance_double(Sncr::Client, exchange_token: token)
      auth = described_class.new(base_url: "x", client_url: "y", client: client)

      expect(auth.exchange_session!(session_id: "sess")).to eq(token)
      expect(client).to have_received(:exchange_token).with(session_id: "sess")
    end
  end
end
