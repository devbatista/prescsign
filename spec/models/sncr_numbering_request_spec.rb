require "rails_helper"

RSpec.describe SncrNumberingRequest do
  include WebSpecHelpers

  let(:organization) { create_organization }
  let(:user) do
    u = create_user(organization: organization)
    create_membership(user: u, organization: organization, role: "doctor")
    create_doctor_profile(user: u)
    u.reload
  end
  let(:profile) { user.doctor_profile }

  def build_request(**attrs)
    described_class.new(
      {
        doctor_profile: profile, sncr_type: "NRB", endpoint: "notificacao", origin: "manual",
        status: "pending", requested_quantity: 50, council: "CRM",
        license_number: profile.license_number, license_state: profile.license_state,
        requested_at: Time.current
      }.merge(attrs)
    )
  end

  def create_request(**attrs)
    build_request(**attrs).tap(&:save!)
  end

  describe "validações" do
    it "aceita uma solicitação pendente sem desfecho" do
      expect(build_request).to be_valid
    end

    it "recusa tipo, endpoint, status e origem fora das listas" do
      expect(build_request(sncr_type: "XX")).not_to be_valid
      expect(build_request(endpoint: "outro")).not_to be_valid
      expect(build_request(status: "cancelado")).not_to be_valid
      expect(build_request(origin: "magia")).not_to be_valid
    end

    it "recusa quantidade não positiva" do
      expect(build_request(requested_quantity: 0)).not_to be_valid
    end

    it "exige o snapshot da inscrição" do
      expect(build_request(council: nil)).not_to be_valid
      expect(build_request(license_number: nil)).not_to be_valid
      expect(build_request(license_state: nil)).not_to be_valid
    end
  end

  describe "coerência do ciclo de vida" do
    it "recusa pendente que já tenha desfecho" do
      expect(build_request(status: "pending", completed_at: Time.current)).not_to be_valid
      expect(build_request(status: "pending", imported_count: 10)).not_to be_valid
    end

    it "exige desfecho e contagem quando concluída com sucesso" do
      expect(build_request(status: "succeeded", completed_at: Time.current)).not_to be_valid
      expect(build_request(status: "succeeded", imported_count: 10)).not_to be_valid
      expect(build_request(status: "succeeded", imported_count: 10, completed_at: Time.current)).to be_valid
    end

    # failed/unknown podem não ter importado número nenhum — é o caso comum.
    it "aceita falha e desconhecido sem contagem, mas exige o desfecho" do
      expect(build_request(status: "failed", completed_at: Time.current)).to be_valid
      expect(build_request(status: "unknown", completed_at: Time.current)).to be_valid
      expect(build_request(status: "failed")).not_to be_valid
    end

    it "o banco também recusa, não só o modelo" do
      expect {
        described_class.connection.execute(<<~SQL.squish)
          INSERT INTO sncr_numbering_requests
            (id, doctor_profile_id, sncr_type, endpoint, origin, status, requested_quantity,
             completed_at, council, license_number, license_state, requested_at, created_at, updated_at)
          VALUES
            (gen_random_uuid(), '#{profile.id}', 'NRB', 'notificacao', 'manual', 'pending', 50,
             NOW(), 'CRM', '123', 'SP', NOW(), NOW(), NOW())
        SQL
      }.to raise_error(ActiveRecord::StatementInvalid, /chk_sncr_numbering_requests_lifecycle_consistency/)
    end
  end

  describe ".endpoint_for" do
    it "roteia RCE e RET para o especial/retenção e o resto para notificação" do
      expect(described_class.endpoint_for("RCE")).to eq("especial_retencao")
      expect(described_class.endpoint_for("RET")).to eq("especial_retencao")
      expect(described_class.endpoint_for("NRB")).to eq("notificacao")
    end
  end

  describe "#quota_weight" do
    it "usa o que a Anvisa entregou quando o desfecho é conhecido" do
      request = create_request(status: "succeeded", requested_quantity: 50, imported_count: 12,
                               completed_at: Time.current)

      expect(request.quota_weight).to eq(12)
    end

    it "usa o que pedimos enquanto não sabemos — conservador de propósito" do
      expect(create_request(requested_quantity: 50).quota_weight).to eq(50)
    end
  end

  describe ".counts_against_quota" do
    it "conta pendente, sucesso e desconhecido, e ignora falha" do
      pendente = create_request
      sucesso = create_request(status: "succeeded", imported_count: 5, completed_at: Time.current)
      desconhecido = create_request(status: "unknown", completed_at: Time.current)
      create_request(status: "failed", completed_at: Time.current)

      expect(described_class.counts_against_quota.pluck(:id))
        .to match_array([ pendente.id, sucesso.id, desconhecido.id ])
    end
  end

  describe "#stale_pending?" do
    it "é falso enquanto a chamada ainda pode estar em voo" do
      expect(create_request(requested_at: 1.minute.ago)).not_to be_stale_pending
    end

    it "é verdadeiro passado o prazo de tolerância" do
      request = create_request(requested_at: described_class::PENDING_GRACE.ago - 1.minute)

      expect(request).to be_stale_pending
    end

    it "não se aplica a solicitação já concluída" do
      request = create_request(status: "succeeded", imported_count: 1, completed_at: Time.current,
                               requested_at: 1.day.ago)

      expect(request).not_to be_stale_pending
    end
  end
end
