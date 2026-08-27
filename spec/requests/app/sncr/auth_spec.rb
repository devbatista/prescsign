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

    it "em modo simulado emite o token na hora, sem redirecionar ao Gov.br" do
      with_sncr_fake do
        get "/sncr/auth/start", params: { state: "/sncr/numberings" }
      end

      expect(response).to redirect_to("/sncr/numberings")
      expect(flash[:notice]).to include("simulado")
      expect(@token_backing[user.id]).to be_present
    end

    it "volta ao painel com alerta genérico quando a configuração falha" do
      auth = instance_double(Sncr::Authentication)
      allow(Sncr::Authentication).to receive(:new).and_return(auth)
      allow(auth).to receive(:login_url)
        .and_raise(Sncr::Error, "A Anvisa só aceita client_url de domínio .br (recebido: http://app.prescsign.local)")

      get "/sncr/auth/start"

      expect(response).to redirect_to(app_root_path)
      expect(flash[:alert]).to include("Não foi possível conectar ao SNCR")
      # O texto técnico é diagnóstico do time — vai para log/Sentry, nunca à tela.
      expect(flash[:alert]).not_to include("client_url")
      expect(flash[:alert]).not_to include("prescsign.local")
    end

    it "alerta o time quando a falha é de configuração" do
      auth = instance_double(Sncr::Authentication)
      allow(Sncr::Authentication).to receive(:new).and_return(auth)
      allow(auth).to receive(:login_url).and_raise(Sncr::Error, "client_url inválido")
      allow(Observability::CriticalAlertService).to receive(:notify!)

      get "/sncr/auth/start"

      expect(Observability::CriticalAlertService)
        .to have_received(:notify!).with(hash_including(category: "sncr_auth_config"))
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

    it "redireciona com alerta genérico quando a troca de token falha" do
      auth = instance_double(Sncr::Authentication)
      allow(Sncr::Authentication).to receive(:new).and_return(auth)
      allow(auth).to receive(:exchange_session!)
        .and_raise(Sncr::Error, "SNCR retornou HTTP 401: Sessão inválida ou expirada")
      allow(Observability::CriticalAlertService).to receive(:notify!)

      get "/sncr/auth/callback", params: { session_id: "x" }

      expect(response).to redirect_to(app_root_path)
      expect(flash[:alert]).to include("Tente conectar novamente")
      expect(flash[:alert]).not_to include("HTTP 401")
      # Sessão expirada é condição cotidiana: não vira alerta crítico.
      expect(Observability::CriticalAlertService).not_to have_received(:notify!)
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
