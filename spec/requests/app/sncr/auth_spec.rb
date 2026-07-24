require "rails_helper"

RSpec.describe "App::Sncr::Auth", type: :request do
  let(:organization) { create_organization }
  let(:user) do
    u = create_user(organization: organization)
    create_membership(user: u, organization: organization, role: "doctor")
    create_doctor_profile(user: u)
    u
  end

  before do
    sign_in_web(user)
    use_app_host!
  end

  describe "GET /sncr/auth/start" do
    it "redireciona para a URL de login do SNCR" do
      auth = instance_double(Sncr::Authentication, login_url: "https://sncr.example/auth/login?client_url=cb")
      allow(Sncr::Authentication).to receive(:new).and_return(auth)

      get "/sncr/auth/start"

      expect(response).to redirect_to("https://sncr.example/auth/login?client_url=cb")
    end

    it "volta ao painel com alerta quando a configuração falha" do
      auth = instance_double(Sncr::Authentication)
      allow(Sncr::Authentication).to receive(:new).and_return(auth)
      allow(auth).to receive(:login_url).and_raise(Sncr::Error, "sem callback")

      get "/sncr/auth/start"

      expect(response).to redirect_to(app_root_path)
      expect(flash[:alert]).to include("SNCR")
    end
  end

  describe "GET /sncr/auth/callback" do
    it "guarda o token e redireciona com aviso" do
      token = Sncr::Client::Token.new(access_token: "jwt", token_type: "Bearer")
      auth = instance_double(Sncr::Authentication)
      allow(Sncr::Authentication).to receive(:new).and_return(auth)
      allow(auth).to receive(:exchange_session!).with(session_id: "sess").and_return(token)

      get "/sncr/auth/callback", params: { session_id: "sess" }

      expect(response).to redirect_to(app_root_path)
      expect(flash[:notice]).to include("Autenticado")
    end

    it "redireciona com alerta quando a troca de token falha" do
      auth = instance_double(Sncr::Authentication)
      allow(Sncr::Authentication).to receive(:new).and_return(auth)
      allow(auth).to receive(:exchange_session!).and_raise(Sncr::Error, "sessão expirada")

      get "/sncr/auth/callback", params: { session_id: "x" }

      expect(response).to redirect_to(app_root_path)
      expect(flash[:alert]).to include("Falha")
    end
  end
end
