require "rails_helper"

RSpec.describe Sncr::AutoRefill do
  include WebSpecHelpers

  let(:organization) { create_organization }
  let(:user) do
    u = create_user(organization: organization)
    create_membership(user: u, organization: organization, role: "doctor")
    create_doctor_profile(user: u)
    u.reload
  end
  let(:profile) { user.doctor_profile }
  let(:patient) { create_patient(user: user, organization: organization) }

  # Marca o tipo como "já usado": cria um número e o consome numa receita.
  def consume_one!(sncr_type, consumed_at: Time.current)
    prescription = user.prescriptions.create!(
      patient: patient, organization: organization,
      code: SecureRandom.alphanumeric(10).upcase, status: "draft",
      content: "Clonazepam 2mg", issued_on: Date.current, sncr_type: sncr_type
    )
    SncrNumbering.import_numbers!(
      doctor_profile: profile, sncr_type: sncr_type, numbers: [ "2411.1-00.#{rand(10**7).to_s.rjust(7, '0')}" ]
    )
    numbering = SncrNumbering.consume_next!(
      doctor_profile: profile, sncr_type: sncr_type, prescription: prescription
    )
    numbering.update_columns(consumed_at: consumed_at)
    numbering
  end

  def stock!(sncr_type, count)
    numbers = Array.new(count) { |i| "2999.1-00.#{(i + 1).to_s.rjust(7, '0')}" }
    SncrNumbering.import_numbers!(doctor_profile: profile, sncr_type: sncr_type, numbers: numbers)
  end

  describe ".eligible_types" do
    it "reabastece tipo já usado e com saldo baixo" do
      consume_one!("NRB")

      expect(described_class.eligible_types(doctor_profile: profile)).to include("NRB")
    end

    # A regra que protege a cota: puxar tipo que o médico não pratica gera
    # número parado e, em RCE/RET, desperdiça uma das 3 solicitações do mês.
    it "nunca reabastece tipo que o médico nunca usou" do
      expect(described_class.eligible_types(doctor_profile: profile)).to be_empty
    end

    it "ignora uso antigo demais para ser prática corrente" do
      consume_one!("NRB", consumed_at: described_class::USAGE_LOOKBACK.ago - 1.day)

      expect(described_class.eligible_types(doctor_profile: profile)).to be_empty
    end

    it "não reabastece quando o saldo está acima do limiar" do
      consume_one!("NRB")
      stock!("NRB", Rails.application.config.x.sncr.refill_threshold_notificacao + 1)

      expect(described_class.eligible_types(doctor_profile: profile)).to be_empty
    end

    it "não reabastece quando a cota não permite" do
      consume_one!("NRB")
      SncrNumberingRequest.create!(
        doctor_profile: profile, sncr_type: "NRB", endpoint: "notificacao", origin: "manual",
        status: "succeeded", requested_quantity: 50, imported_count: 50,
        council: "CRM", license_number: profile.license_number, license_state: profile.license_state,
        requested_at: Time.current, completed_at: Time.current
      )

      expect(described_class.eligible_types(doctor_profile: profile)).to be_empty
    end

    # Sem isto, dez assinaturas seguidas viram dez chamadas à Anvisa — e em
    # RCE/RET, três requisições mensais queimadas num piscar.
    it "respeita o cooldown entre reabastecimentos do mesmo tipo" do
      consume_one!("NRB")
      SncrNumberingRequest.create!(
        doctor_profile: profile, sncr_type: "NRB", endpoint: "notificacao", origin: "auto_refill",
        status: "succeeded", requested_quantity: 1, imported_count: 1,
        council: "CRM", license_number: profile.license_number, license_state: profile.license_state,
        requested_at: 5.minutes.ago, completed_at: 5.minutes.ago
      )

      expect(described_class.eligible_types(doctor_profile: profile)).to be_empty
    end

    it "volta a reabastecer passado o cooldown" do
      consume_one!("NRB")
      SncrNumberingRequest.create!(
        doctor_profile: profile, sncr_type: "NRB", endpoint: "notificacao", origin: "auto_refill",
        status: "succeeded", requested_quantity: 1, imported_count: 1,
        council: "CRM", license_number: profile.license_number, license_state: profile.license_state,
        requested_at: described_class::COOLDOWN.ago - 1.minute,
        completed_at: described_class::COOLDOWN.ago - 1.minute
      )

      expect(described_class.eligible_types(doctor_profile: profile)).to include("NRB")
    end

    it "restringe ao tipo pedido em `only`" do
      consume_one!("NRB")
      consume_one!("NRA")

      expect(described_class.eligible_types(doctor_profile: profile, only: "NRB")).to eq([ "NRB" ])
    end

    it "não faz nada quando o reabastecimento está desligado" do
      consume_one!("NRB")
      allow(Rails.application.config.x.sncr).to receive(:auto_refill).and_return(false)

      expect(described_class.eligible_types(doctor_profile: profile)).to be_empty
    end
  end

  describe ".enqueue_for" do
    it "enfileira um job por tipo elegível" do
      consume_one!("NRB")

      expect { described_class.enqueue_for(user: user, doctor_profile: profile) }
        .to have_enqueued_job(Sncr::AutoRefillJob)
        .with(user_id: user.id, doctor_profile_id: profile.id, sncr_type: "NRB")
    end

    it "não enfileira nada quando não há tipo elegível" do
      expect { described_class.enqueue_for(user: user, doctor_profile: profile) }
        .not_to have_enqueued_job(Sncr::AutoRefillJob)
    end

    # Reabastecer é conveniência: uma falha aqui não pode derrubar a assinatura
    # que acabou de dar certo.
    it "engole a falha em vez de propagar" do
      allow(described_class).to receive(:eligible_types).and_raise(StandardError, "boom")

      expect { described_class.enqueue_for(user: user, doctor_profile: profile) }.not_to raise_error
    end
  end
end
