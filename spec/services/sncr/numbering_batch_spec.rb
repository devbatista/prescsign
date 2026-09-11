require "rails_helper"

RSpec.describe Sncr::NumberingBatch do
  include WebSpecHelpers

  let(:organization) { create_organization }
  let(:user) do
    u = create_user(organization: organization)
    create_membership(user: u, organization: organization, role: "doctor")
    create_doctor_profile(user: u)
    u.reload
  end
  let(:profile) { user.doctor_profile }

  it "usa a Notificação de Receita para NRA/NRB/NRB2/NRR/NRT e importa a lista" do
    client = instance_double(Sncr::Client)
    expect(client).to receive(:request_notificacao!).with(
      receita: "NRB", conselho: "CRM", uf: profile.license_state,
      documento: profile.license_number,
      quantidade: Sncr::NumberingQuota::NOTIFICACAO_DAILY_LIMIT
    ).and_return(
      Sncr::Client::Notificacao.new(numbers: %w[2411.1-00.0000001 2411.1-00.0000002], balance: 48, message: nil)
    )

    request = described_class.request!(doctor_profile: profile, sncr_type: "NRB", client: client)

    expect(request).to be_succeeded
    expect(request.imported_count).to eq(2)
    expect(SncrNumbering.balance_for(profile)).to eq("NRB" => 2)
  end

  it "usa o Controle Especial/Retenção para RCE/RET e expande a faixa" do
    client = instance_double(Sncr::Client)
    expect(client).to receive(:request_especial_retencao!).with(
      conselho: "CRM", tipo: "RCE", documento: profile.license_number,
      uf: profile.license_state, cnpj: Rails.application.config.x.sncr.platform_cnpj
    ).and_return(
      Sncr::Client::EspecialRetencao.new(
        range_start: "2602.6-53.0000001", range_end: "2602.6-53.0000005", quantity: 5, message: nil
      )
    )

    request = described_class.request!(doctor_profile: profile, sncr_type: "RCE", client: client)

    expect(request.imported_count).to eq(5)
    expect(SncrNumbering.balance_for(profile)).to eq("RCE" => 5)
  end

  it "recusa tipo fora dos SNCR_TYPES sem chamar a API" do
    client = instance_double(Sncr::Client)

    expect { described_class.request!(doctor_profile: profile, sncr_type: "XX", client: client) }
      .to raise_error(Sncr::Error, /Tipo de receita inválido/)
  end

  it "importa numeração simulada de ponta a ponta quando o modo fake está ligado" do
    request = with_sncr_fake { described_class.request!(doctor_profile: profile, sncr_type: "NRB") }

    expect(request.imported_count).to eq(Sncr::NumberingQuota::NOTIFICACAO_DAILY_LIMIT)
    expect(SncrNumbering.for_doctor(profile).of_type("NRB").pluck(:number))
      .to all(match(SncrNumbering::NUMBER_FORMAT))
  end

  describe "registro da solicitação" do
    it "grava o saldo remoto e o aviso da Anvisa, que antes eram descartados" do
      client = instance_double(Sncr::Client)
      allow(client).to receive(:request_notificacao!).and_return(
        Sncr::Client::Notificacao.new(
          numbers: %w[2411.1-00.0000001], balance: 42, message: "Saldo inferior a 50 receitas."
        )
      )

      request = described_class.request!(doctor_profile: profile, sncr_type: "NRB", client: client)

      expect(request.remote_balance).to eq(42)
      expect(request.remote_message).to eq("Saldo inferior a 50 receitas.")
    end

    it "vincula cada número importado à solicitação que o trouxe" do
      client = instance_double(Sncr::Client)
      allow(client).to receive(:request_notificacao!).and_return(
        Sncr::Client::Notificacao.new(numbers: %w[2411.1-00.0000001], balance: nil, message: nil)
      )

      request = described_class.request!(doctor_profile: profile, sncr_type: "NRB", client: client)

      expect(SncrNumbering.for_doctor(profile).pluck(:sncr_numbering_request_id)).to eq([ request.id ])
    end

    it "guarda o snapshot da inscrição, porque o limite da Anvisa é por inscrição" do
      client = instance_double(Sncr::Client)
      allow(client).to receive(:request_notificacao!).and_return(
        Sncr::Client::Notificacao.new(numbers: [], balance: nil, message: nil)
      )

      request = described_class.request!(doctor_profile: profile, sncr_type: "NRB", client: client)

      expect(request).to have_attributes(
        council: "CRM",
        license_number: profile.license_number,
        license_state: profile.license_state
      )
    end
  end

  describe "desfechos de erro" do
    # A distinção que protege a cota: recusa da Anvisa não queima requisição,
    # mas timeout pode ter sido processado do outro lado.
    it "marca `failed` quando a Anvisa recusa (4xx) — não conta para a cota" do
      client = instance_double(Sncr::Client)
      allow(client).to receive(:request_notificacao!)
        .and_raise(Sncr::Error.new("Inscrição divergente", http_status: 400))

      expect { described_class.request!(doctor_profile: profile, sncr_type: "NRB", client: client) }
        .to raise_error(Sncr::Error)

      request = SncrNumberingRequest.last
      expect(request.status).to eq("failed")
      expect(request.error_message).to include("Inscrição divergente")
      expect(SncrNumberingRequest.counts_against_quota).to be_empty
    end

    it "marca `unknown` quando não houve resposta — conta para a cota" do
      client = instance_double(Sncr::Client)
      allow(client).to receive(:request_notificacao!).and_raise(Sncr::TransportError, "SNCR indisponível")

      expect { described_class.request!(doctor_profile: profile, sncr_type: "NRB", client: client) }
        .to raise_error(Sncr::TransportError)

      expect(SncrNumberingRequest.last.status).to eq("unknown")
      expect(SncrNumberingRequest.counts_against_quota.count).to eq(1)
    end

    it "marca `unknown` quando a Anvisa devolve 5xx" do
      client = instance_double(Sncr::Client)
      allow(client).to receive(:request_notificacao!)
        .and_raise(Sncr::Error.new("Erro interno", http_status: 502))

      expect { described_class.request!(doctor_profile: profile, sncr_type: "NRB", client: client) }
        .to raise_error(Sncr::Error)

      expect(SncrNumberingRequest.last.status).to eq("unknown")
    end
  end

  describe "cota" do
    it "barra antes de tocar o cliente quando a cota do dia acabou" do
      client = instance_double(Sncr::Client)
      SncrNumberingRequest.create!(
        doctor_profile: profile, sncr_type: "NRB", endpoint: "notificacao", origin: "manual",
        status: "succeeded", requested_quantity: 50, imported_count: 50,
        council: "CRM", license_number: profile.license_number, license_state: profile.license_state,
        requested_at: Time.current, completed_at: Time.current
      )

      expect(client).not_to receive(:request_notificacao!)
      expect { described_class.request!(doctor_profile: profile, sncr_type: "NRB", client: client) }
        .to raise_error(Sncr::QuotaExceeded, /cota da Anvisa é diária/)
    end

    # Ponta a ponta pelo FakeClient, que simula os mesmos limites da Anvisa: as
    # duas primeiras passam, a terceira é barrada por nós — antes da chamada, e
    # com motivo legível, em vez do erro opaco que a Anvisa devolveria na quarta.
    it "barra a 4ª solicitação de RCE/RET do mês, somando os dois tipos" do
      with_sncr_fake do
        with_sncr_platform_cnpj do
          described_class.request!(doctor_profile: profile, sncr_type: "RCE")
          described_class.request!(doctor_profile: profile, sncr_type: "RET")
          described_class.request!(doctor_profile: profile, sncr_type: "RCE")

          expect { described_class.request!(doctor_profile: profile, sncr_type: "RET") }
            .to raise_error(Sncr::QuotaExceeded, /3 solicitações de RCE\/RET deste mês/)
        end
      end

      expect(SncrNumberingRequest.counts_against_quota.count).to eq(3)
    end

    it "pede só o que resta da cota do dia, em vez dos 50 fixos" do
      SncrNumberingRequest.create!(
        doctor_profile: profile, sncr_type: "NRB", endpoint: "notificacao", origin: "manual",
        status: "succeeded", requested_quantity: 20, imported_count: 20,
        council: "CRM", license_number: profile.license_number, license_state: profile.license_state,
        requested_at: Time.current, completed_at: Time.current
      )

      client = instance_double(Sncr::Client)
      expect(client).to receive(:request_notificacao!).with(hash_including(quantidade: 30)).and_return(
        Sncr::Client::Notificacao.new(numbers: [], balance: nil, message: nil)
      )

      described_class.request!(doctor_profile: profile, sncr_type: "NRB", client: client)
    end
  end
end
