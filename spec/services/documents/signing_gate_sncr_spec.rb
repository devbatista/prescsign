require "rails_helper"
require "securerandom"

# Portão SNCR na assinatura: receita controlada consome um número do pool do
# prescritor de forma atômica com a assinatura (ver Sncr::NumberingAssignment e
# Documents::SigningService).
RSpec.describe Documents::SigningService, "portão de numeração SNCR" do
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

  def controlled_document(sncr_type:)
    prescription = user.prescriptions.create!(
      patient: patient, organization: organization,
      code: SecureRandom.alphanumeric(10).upcase, status: "draft",
      content: "Clonazepam 2mg", issued_on: Date.current, sncr_type: sncr_type
    )
    Documents::LifecycleService.new(actor: user).create_with_initial_version!(
      user: user, patient: patient, documentable: prescription,
      unit: organization.default_unit, kind: "prescription",
      issued_on: prescription.issued_on, content: prescription.content
    )
    prescription.reload.document
  end

  def stubbed_service
    provider = instance_double(Signatures::InternalProvider)
    allow(provider).to receive(:sign_pdf!).and_return(
      Signatures::SignatureResult.new(
        signed_pdf: "%PDF signed", provider: "test_provider",
        method: "eval_crypto_cubo_pades", signed_at: Time.current,
        timestamped: true, validation_status: "valid"
      )
    )
    allow(Documents::PdfRenderer).to receive(:new).and_return(
      instance_double(Documents::PdfRenderer, render: "%PDF unsigned")
    )
    described_class.new(actor: user, signature_provider: provider)
  end

  it "consome um número do pool ao assinar receita controlada" do
    SncrNumbering.import_numbers!(doctor_profile: profile, sncr_type: "NRB", numbers: [ "2411.1-00.0000001" ])
    document = controlled_document(sncr_type: "NRB")

    stubbed_service.sign!(document: document)

    document.reload
    expect(document.status).to eq("sent")
    numbering = SncrNumbering.find_by(number: "2411.1-00.0000001")
    expect(numbering.status).to eq("consumed")
    expect(numbering.prescription_id).to eq(document.documentable_id)
  end

  it "bloqueia a assinatura e faz rollback quando o pool do tipo está vazio" do
    document = controlled_document(sncr_type: "RCE")

    expect { stubbed_service.sign!(document: document) }.to raise_error(SncrNumbering::PoolEmpty)

    document.reload
    expect(document.status).to eq("issued")
    expect(document.current_version).to eq(1)
    expect(document.documentable.status).to eq("draft")
  end

  it "não dispara alerta crítico de falha de assinatura para pool vazio" do
    document = controlled_document(sncr_type: "RCE")
    allow(Observability::CriticalAlertService).to receive(:notify!)

    expect { stubbed_service.sign!(document: document) }.to raise_error(SncrNumbering::PoolEmpty)

    expect(Observability::CriticalAlertService).not_to have_received(:notify!)
  end
end
