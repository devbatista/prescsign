require "rails_helper"
require "securerandom"

# Destino da numeração SNCR quando o documento que a consumiu é revogado.
# Cobre os DOIS caminhos de revogação — o médico revogando e o sistema revogando
# ao detectar adulteração —, porque corrigir só o primeiro deixaria sem rastro
# justamente o caso adversarial.
RSpec.describe Sncr::NumberingRevocation do
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

  # Receita controlada com um número do pool já consumido, que é o estado em que
  # a revogação encontra o documento na vida real (o consumo acontece na
  # assinatura, dentro da transação — ver Sncr::NumberingAssignment).
  def controlled_prescription_with_numbering(number: "2411.1-00.0000001")
    prescription = create_prescription_document(
      user: user, patient: patient, organization: organization,
      content: "Clonazepam 2mg", sncr_type: "NRA"
    )
    SncrNumbering.import_numbers!(doctor_profile: profile, sncr_type: "NRA", numbers: [ number ])
    SncrNumbering.consume_next!(doctor_profile: profile, sncr_type: "NRA", prescription: prescription)
    prescription.reload
  end

  def lifecycle
    Documents::LifecycleService.new(actor: user)
  end

  describe "revogação pelo médico (Documents::LifecycleService#revoke!)" do
    it "marca a numeração como revogada" do
      prescription = controlled_prescription_with_numbering

      lifecycle.revoke!(documentable: prescription, reason: "Dose incorreta")

      numbering = prescription.sncr_numbering.reload
      expect(numbering.revoked_at).to be_present
      expect(numbering).to be_revoked
    end

    it "NÃO devolve o número ao pool" do
      prescription = controlled_prescription_with_numbering

      lifecycle.revoke!(documentable: prescription, reason: "Dose incorreta")

      numbering = prescription.sncr_numbering.reload
      # Continua consumido e vinculado à receita: o número já foi impresso num
      # documento assinado e é único nacionalmente. Devolvê-lo faria a próxima
      # receita sair com o mesmo número.
      expect(numbering.status).to eq("consumed")
      expect(numbering.prescription_id).to eq(prescription.id)
      expect(SncrNumbering.available.for_doctor(profile).count).to eq(0)
    end

    it "não quebra quando a receita é comum (sem numeração)" do
      prescription = create_prescription_document(
        user: user, patient: patient, organization: organization
      )

      expect {
        lifecycle.revoke!(documentable: prescription, reason: "Erro de digitação")
      }.not_to raise_error

      expect(prescription.reload.document.status).to eq("revoked")
    end
  end

  describe "revogação por adulteração (Documents::IntegrityService)" do
    it "marca a numeração como revogada" do
      prescription = controlled_prescription_with_numbering
      service = Documents::IntegrityService.new(actor: user)

      service.send(:revoke_for_integrity!, prescription.document, { checksum_source: "pdf" })

      numbering = prescription.sncr_numbering.reload
      expect(numbering.revoked_at).to be_present
      expect(numbering.status).to eq("consumed")
    end
  end

  describe ".revoke_for!" do
    it "é idempotente e preserva a data do primeiro registro" do
      prescription = controlled_prescription_with_numbering
      first = Time.current - 1.day

      described_class.revoke_for!(prescription, at: first)
      described_class.revoke_for!(prescription.reload, at: Time.current)

      expect(prescription.sncr_numbering.reload.revoked_at).to be_within(1.second).of(first)
    end

    it "é no-op para documento que não é receita (atestado)" do
      expect(described_class.revoke_for!(instance_double(MedicalCertificate))).to be_nil
    end
  end

  describe "escopo .revoked" do
    it "lista apenas as numerações cujo documento caiu" do
      revoked = controlled_prescription_with_numbering(number: "2411.1-00.0000001")
      SncrNumbering.import_numbers!(
        doctor_profile: profile, sncr_type: "NRA", numbers: [ "2411.1-00.0000002" ]
      )

      lifecycle.revoke!(documentable: revoked, reason: "Dose incorreta")

      expect(SncrNumbering.revoked.pluck(:number)).to eq([ "2411.1-00.0000001" ])
    end
  end
end
