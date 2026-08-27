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
      documento: profile.license_number, quantidade: described_class::NOTIFICACAO_BATCH_SIZE
    ).and_return(
      Sncr::Client::Notificacao.new(numbers: %w[2411.1-00.0000001 2411.1-00.0000002], balance: 48, message: nil)
    )

    imported = described_class.request!(doctor_profile: profile, sncr_type: "NRB", client: client)

    expect(imported).to eq(2)
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

    imported = described_class.request!(doctor_profile: profile, sncr_type: "RCE", client: client)

    expect(imported).to eq(5)
    expect(SncrNumbering.balance_for(profile)).to eq("RCE" => 5)
  end

  it "recusa tipo fora dos SNCR_TYPES sem chamar a API" do
    client = instance_double(Sncr::Client)

    expect { described_class.request!(doctor_profile: profile, sncr_type: "XX", client: client) }
      .to raise_error(Sncr::Error, /Tipo de receita inválido/)
  end

  it "importa numeração simulada de ponta a ponta quando o modo fake está ligado" do
    imported = with_sncr_fake { described_class.request!(doctor_profile: profile, sncr_type: "NRB") }

    expect(imported).to eq(described_class::NOTIFICACAO_BATCH_SIZE)
    expect(SncrNumbering.for_doctor(profile).of_type("NRB").pluck(:number))
      .to all(match(SncrNumbering::NUMBER_FORMAT))
  end
end
