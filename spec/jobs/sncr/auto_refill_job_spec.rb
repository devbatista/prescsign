require "rails_helper"

RSpec.describe Sncr::AutoRefillJob do
  include WebSpecHelpers

  let(:organization) { create_organization }
  let(:user) do
    u = create_user(organization: organization)
    create_membership(user: u, organization: organization, role: "doctor")
    create_doctor_profile(user: u)
    u.reload
  end
  let(:profile) { user.doctor_profile }

  def perform!
    described_class.perform_now(user_id: user.id, doctor_profile_id: profile.id, sncr_type: "NRB")
  end

  before { allow(Sncr::AutoRefill).to receive(:eligible_types).and_return([ "NRB" ]) }

  # A restrição dura do desenho: o token do Gov.br é artefato de sessão e pode
  # ter expirado entre o enfileiramento e a execução.
  it "não faz nada quando não há token do Gov.br" do
    stub_sncr_token_store

    expect(Sncr::NumberingBatch).not_to receive(:request!)
    expect { perform! }.not_to raise_error
  end

  it "lê o token do TokenStore, e não do payload do job" do
    backing = stub_sncr_token_store
    backing[user.id] = "jwt-da-sessao"
    allow(Sncr::NumberingBatch).to receive(:request!)

    perform!

    expect(Sncr::NumberingBatch).to have_received(:request!)
      .with(hash_including(access_token: "jwt-da-sessao", origin: "auto_refill", sncr_type: "NRB"))
  end

  it "não faz nada quando o prescritor não existe mais" do
    stub_sncr_token_store

    expect(Sncr::NumberingBatch).not_to receive(:request!)
    described_class.perform_now(user_id: user.id, doctor_profile_id: SecureRandom.uuid, sncr_type: "NRB")
  end

  it "não pede quando deixou de ser elegível entre o enfileiramento e a execução" do
    backing = stub_sncr_token_store
    backing[user.id] = "jwt"
    allow(Sncr::AutoRefill).to receive(:eligible_types).and_return([])

    expect(Sncr::NumberingBatch).not_to receive(:request!)
    perform!
  end

  describe "desfechos" do
    before do
      backing = stub_sncr_token_store
      backing[user.id] = "jwt"
    end

    # Cota estourada e recusa da Anvisa são o sistema funcionando: viram log, e
    # nunca alerta crítico nem retry.
    it "engole Sncr::QuotaExceeded sem alertar o time" do
      allow(Sncr::NumberingBatch).to receive(:request!).and_raise(Sncr::QuotaExceeded, "cota")
      allow(Observability::CriticalAlertService).to receive(:notify!)

      expect { perform! }.not_to raise_error
      expect(Observability::CriticalAlertService).not_to have_received(:notify!)
    end

    it "engole Sncr::Error sem alertar o time" do
      allow(Sncr::NumberingBatch).to receive(:request!).and_raise(Sncr::Error, "indisponível")
      allow(Observability::CriticalAlertService).to receive(:notify!)

      expect { perform! }.not_to raise_error
      expect(Observability::CriticalAlertService).not_to have_received(:notify!)
    end

    it "alerta o time em falha inesperada, sem propagar" do
      allow(Sncr::NumberingBatch).to receive(:request!).and_raise(StandardError, "boom")
      allow(Observability::CriticalAlertService).to receive(:notify!)

      expect { perform! }.not_to raise_error
      expect(Observability::CriticalAlertService)
        .to have_received(:notify!).with(hash_including(category: "sncr_auto_refill_failure"))
    end
  end
end
