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
    @token_backing = stub_sncr_token_store
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

      expect(@token_backing[user.id]).to eq("jwt")
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

  # A Anvisa devolve o navegador para a origem do app (raiz do `app.`) com
  # `?session_id`, não para o path dedicado — a rota-raiz condicional captura isso.
  describe "GET / (landing do SNCR na raiz)" do
    it "com session_id, troca o token e redireciona (mesmo comportamento do callback)" do
      token = Sncr::Client::Token.new(access_token: "jwt", token_type: "Bearer")
      auth = instance_double(Sncr::Authentication)
      allow(Sncr::Authentication).to receive(:new).and_return(auth)
      allow(auth).to receive(:exchange_session!).with(session_id: "sess").and_return(token)

      get "/", params: { session_id: "sess", state: "/sncr/numberings" }

      expect(@token_backing[user.id]).to eq("jwt")
      expect(response).to redirect_to("/sncr/numberings")
      expect(flash[:notice]).to include("Autenticado")
    end

    it "sem session_id, não aciona o SNCR e cai no dashboard" do
      allow(Sncr::Authentication).to receive(:new).and_call_original

      get "/"

      expect(Sncr::Authentication).not_to have_received(:new)
      expect(response).to have_http_status(:ok)
    end
  end
end
