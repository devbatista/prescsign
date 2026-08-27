require "rails_helper"

RSpec.describe "App::Sncr::Numberings", type: :request do
  let(:organization) { create_organization }

  context "como médico" do
    let(:user) do
      u = create_user(organization: organization)
      create_membership(user: u, organization: organization, role: "doctor")
      create_doctor_profile(user: u)
      u
    end

    before do
      sign_in_web(user)
      use_app_host!
      stub_sncr_token_store
    end

    it "mostra a área com o item de menu, status de conexão e saldo" do
      get "/sncr/numberings"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Numerações de Controlados")
      expect(response.body).to include("Numerações SNCR") # item de menu
      expect(response.body).to include("Conectar ao Gov.br")
    end

    it "rejeita um tipo de receita inválido" do
      post "/sncr/numberings", params: { sncr_type: "XYZ" }

      expect(response).to redirect_to(sncr_numberings_path)
      follow_redirect!
      expect(response.body).to include("inválido")
    end

    it "redireciona ao Gov.br quando ainda não está conectado" do
      post "/sncr/numberings", params: { sncr_type: "NRA" }

      expect(response).to redirect_to(sncr_auth_start_path(state: sncr_numberings_path))
    end

    it "solicita um lote e importa ao pool quando conectado" do
      authenticate_in_sncr!

      client = instance_double(::Sncr::Client)
      allow(::Sncr::Client).to receive(:new).and_return(client)
      allow(client).to receive(:request_notificacao!).and_return(
        ::Sncr::Client::Notificacao.new(
          numbers: %w[2411.1-00.0000001 2411.1-00.0000002],
          balance: 48,
          message: nil
        )
      )

      expect {
        post "/sncr/numberings", params: { sncr_type: "NRA" }
      }.to change(::SncrNumbering, :count).by(2)

      expect(response).to redirect_to(sncr_numberings_path)
      follow_redirect!
      expect(response.body).to include("2 numeração")
    end

    # Caminho completo do modo simulado, sem nenhum dublê: conectar (sem Gov.br)
    # e solicitar o lote (sem Anvisa), exatamente o que o médico faz na tela.
    context "com SNCR_FAKE ligado" do
      it "conecta sem sair do app e importa um lote de 50 numerações" do
        with_sncr_fake do
          get "/sncr/auth/start", params: { state: sncr_numberings_path }
          expect(response).to redirect_to(sncr_numberings_path)

          expect {
            post "/sncr/numberings", params: { sncr_type: "NRA" }
          }.to change(::SncrNumbering, :count).by(50)

          expect(response).to redirect_to(sncr_numberings_path)
          follow_redirect!
        end

        expect(response.body).to include("50 numeração")
        numbers = ::SncrNumbering.for_doctor(user.doctor_profile).of_type("NRA").pluck(:number)
        expect(numbers).to all(match(::SncrNumbering::NUMBER_FORMAT))
      end

      it "mostra o aviso de que as numerações não têm validade sanitária" do
        with_sncr_fake { get "/sncr/numberings" }

        expect(response.body).to include("Modo simulado")
        expect(response.body).to include("Conectar (simulado)")
      end
    end

    # Autentica no SNCR passando pelo callback (grava o token no TokenStore).
    def authenticate_in_sncr!
      auth = instance_double(::Sncr::Authentication)
      allow(::Sncr::Authentication).to receive(:new).and_return(auth)
      allow(auth).to receive(:exchange_session!).and_return(
        ::Sncr::Client::Token.new(access_token: "jwt", token_type: "Bearer")
      )
      get "/sncr/auth/callback", params: { session_id: "sess" }
    end
  end

  context "como responsável da organização (não médico)" do
    let(:user) { create_org_responsible(organization: organization) }

    before do
      sign_in_web(user)
      use_app_host!
    end

    it "não acessa a área e não vê o item de menu" do
      get "/sncr/numberings"

      expect(response).to redirect_to(app_root_path)
      follow_redirect!
      expect(response.body).not_to include("Numerações SNCR")
    end
  end
end
