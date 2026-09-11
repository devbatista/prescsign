require "rails_helper"

RSpec.describe Sncr::NumberingQuota do
  include WebSpecHelpers

  let(:organization) { create_organization }
  let(:user) do
    u = create_user(organization: organization)
    create_membership(user: u, organization: organization, role: "doctor")
    create_doctor_profile(user: u)
    u.reload
  end
  let(:profile) { user.doctor_profile }

  def record_request(sncr_type:, quantity:, requested_at:, status: "succeeded", imported: nil)
    SncrNumberingRequest.create!(
      doctor_profile: profile,
      sncr_type: sncr_type,
      endpoint: SncrNumberingRequest.endpoint_for(sncr_type),
      origin: "manual",
      status: status,
      requested_quantity: quantity,
      imported_count: status == "succeeded" ? (imported || quantity) : nil,
      council: "CRM",
      license_number: profile.license_number,
      license_state: profile.license_state,
      requested_at: requested_at,
      completed_at: status == "pending" ? nil : requested_at
    )
  end

  def quota(now: Time.current)
    described_class.for(profile, now: now)
  end

  describe "notificação — 50 por tipo, por dia" do
    it "permite quando não houve solicitação hoje" do
      expect(quota.allows?("NRB")).to be(true)
      expect(quota.next_quantity_for("NRB")).to eq(50)
    end

    it "pede só o que resta da cota do dia" do
      record_request(sncr_type: "NRB", quantity: 30, requested_at: Time.current)

      expect(quota.next_quantity_for("NRB")).to eq(20)
    end

    it "bloqueia quando a cota do dia acabou" do
      record_request(sncr_type: "NRB", quantity: 50, requested_at: Time.current)

      expect(quota.allows?("NRB")).to be(false)
      expect(quota.block_reason("NRB")).to match(/cota da Anvisa é diária/)
    end

    # A Anvisa exige mínimo de 10 por requisição: com 5 de saldo, pedir seria
    # recusado com erro opaco.
    it "bloqueia quando resta menos que o mínimo de 10" do
      record_request(sncr_type: "NRB", quantity: 45, requested_at: Time.current)

      expect(quota.allows?("NRB")).to be(false)
      expect(quota.block_reason("NRB")).to match(/no mínimo 10/)
    end

    it "conta por tipo, não no agregado" do
      record_request(sncr_type: "NRB", quantity: 50, requested_at: Time.current)

      expect(quota.allows?("NRA")).to be(true)
    end

    it "não conta o que foi pedido ontem" do
      record_request(sncr_type: "NRB", quantity: 50, requested_at: 1.day.ago)

      expect(quota.allows?("NRB")).to be(true)
    end
  end

  describe "especial/retenção — 3 solicitações e 3.000 números por mês" do
    it "soma RCE e RET no mesmo teto de solicitações" do
      record_request(sncr_type: "RCE", quantity: 1_000, requested_at: Time.current)
      record_request(sncr_type: "RET", quantity: 1_000, requested_at: Time.current)
      record_request(sncr_type: "RCE", quantity: 1_000, requested_at: Time.current)

      expect(quota.especial_requests_this_month).to eq(3)
      expect(quota.allows?("RET")).to be(false)
      expect(quota.block_reason("RET")).to match(/3 solicitações de RCE\/RET deste mês/)
    end

    it "permite enquanto há solicitação sobrando no mês" do
      record_request(sncr_type: "RCE", quantity: 1_000, requested_at: Time.current)

      expect(quota.allows?("RCE")).to be(true)
      expect(quota.next_quantity_for("RCE")).to eq(1_000)
    end

    it "bloqueia quando o próximo bloco ultrapassaria os 3.000 números" do
      record_request(sncr_type: "RCE", quantity: 2_500, requested_at: Time.current)

      expect(quota.block_reason("RCE")).to match(/3000 numerações RCE\/RET no mês/)
    end

    it "não conta o mês passado" do
      record_request(sncr_type: "RCE", quantity: 1_000, requested_at: 45.days.ago)
      record_request(sncr_type: "RCE", quantity: 1_000, requested_at: 45.days.ago)
      record_request(sncr_type: "RCE", quantity: 1_000, requested_at: 45.days.ago)

      expect(quota.allows?("RCE")).to be(true)
    end
  end

  describe "margem do reabastecimento automático" do
    it "para na 2ª de 3, deixando a última para o médico pedir na mão" do
      record_request(sncr_type: "RCE", quantity: 1_000, requested_at: Time.current)
      record_request(sncr_type: "RCE", quantity: 1_000, requested_at: Time.current)

      expect(quota.allows?("RCE", origin: "auto_refill")).to be(false)
      expect(quota.allows?("RCE", origin: "manual")).to be(true)
    end

    it "não restringe a notificação, que tem cota diária e barata" do
      record_request(sncr_type: "NRB", quantity: 10, requested_at: Time.current)

      expect(quota.allows?("NRB", origin: "auto_refill")).to be(true)
    end
  end

  describe "o que conta para a cota" do
    it "conta a pendente, porque pode estar em voo" do
      record_request(sncr_type: "NRB", quantity: 50, requested_at: Time.current, status: "pending")

      expect(quota.allows?("NRB")).to be(false)
    end

    it "conta a desconhecida, porque a Anvisa pode ter processado" do
      record_request(sncr_type: "NRB", quantity: 50, requested_at: Time.current, status: "unknown")

      expect(quota.allows?("NRB")).to be(false)
    end

    it "não conta a recusada, que não chegou a queimar requisição" do
      record_request(sncr_type: "NRB", quantity: 50, requested_at: Time.current, status: "failed")

      expect(quota.allows?("NRB")).to be(true)
    end
  end

  # O app roda em UTC e a Anvisa vira o dia e o mês no horário de Brasília. Sem
  # o fuso certo haveria três horas por dia (e por mês) em que nossa conta e a
  # dela discordam — na fronteira em que o erro é irreversível.
  describe "fuso horário da Anvisa (America/Sao_Paulo)" do
    it "às 01:00 UTC do dia 1º ainda está no mês anterior em Brasília" do
      # 01:00 UTC de 1º de abril = 22:00 de 31 de março em São Paulo.
      marco = Time.utc(2026, 3, 31, 23, 0)
      abril_utc = Time.utc(2026, 4, 1, 1, 0)

      3.times { record_request(sncr_type: "RCE", quantity: 1_000, requested_at: marco) }

      expect(quota(now: abril_utc).especial_requests_this_month).to eq(3)
      expect(quota(now: abril_utc).allows?("RCE")).to be(false)
    end

    it "vira o mês junto com a Anvisa, não três horas antes" do
      marco = Time.utc(2026, 3, 31, 23, 0)
      # 04:00 UTC de 1º de abril = 01:00 de 1º de abril em São Paulo.
      abril_brasilia = Time.utc(2026, 4, 1, 4, 0)

      3.times { record_request(sncr_type: "RCE", quantity: 1_000, requested_at: marco) }

      expect(quota(now: abril_brasilia).especial_requests_this_month).to eq(0)
      expect(quota(now: abril_brasilia).allows?("RCE")).to be(true)
    end
  end

  describe "saldo remoto" do
    it "devolve o último saldo e aviso que a Anvisa reportou para o tipo" do
      antiga = record_request(sncr_type: "NRB", quantity: 10, requested_at: 3.days.ago)
      antiga.update!(remote_balance: 99, remote_message: "antiga")
      recente = record_request(sncr_type: "NRB", quantity: 10, requested_at: 1.day.ago)
      recente.update!(remote_balance: 42, remote_message: "Saldo inferior a 50 receitas.")

      balance, _at = quota.remote_balance("NRB")
      expect(balance).to eq(42)
      expect(quota.remote_message("NRB")).to eq("Saldo inferior a 50 receitas.")
    end

    it "devolve nil quando nunca houve solicitação bem-sucedida do tipo" do
      expect(quota.remote_balance("NRT")).to be_nil
      expect(quota.remote_message("NRT")).to be_nil
    end
  end

  describe "#ensure!" do
    it "levanta QuotaExceeded com a mensagem que vai para a tela" do
      record_request(sncr_type: "NRB", quantity: 50, requested_at: Time.current)

      expect { quota.ensure!("NRB") }
        .to raise_error(Sncr::QuotaExceeded, /cota da Anvisa é diária/)
    end

    it "passa quando há cota" do
      expect(quota.ensure!("NRB")).to be(true)
    end
  end
end
