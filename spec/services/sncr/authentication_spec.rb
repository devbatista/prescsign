require "rails_helper"

RSpec.describe Sncr::Authentication do
  describe "#login_url" do
    it "monta a URL de login com client_url e state" do
      auth = described_class.new(
        base_url: "https://sncr.example/api/v1",
        client_url: "https://app.example/sncr/auth/callback"
      )

      url = auth.login_url(state: "/sncr")

      expect(url).to start_with("https://sncr.example/api/v1/auth/login?")
      expect(url).to include("client_url=https%3A%2F%2Fapp.example%2Fsncr%2Fauth%2Fcallback")
      expect(url).to include("state=%2Fsncr")
    end

    it "omite o state quando ausente" do
      auth = described_class.new(base_url: "https://sncr.example", client_url: "https://app.example/cb")

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
