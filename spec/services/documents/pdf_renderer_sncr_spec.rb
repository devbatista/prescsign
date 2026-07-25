require "rails_helper"

# Passo 7 — PDF do controlado: o template exibe tipo + numeração nacional do SNCR
# quando a receita é controlada. Testa o HTML gerado (sem invocar o wkhtmltopdf).
RSpec.describe Documents::PdfRenderer, "receita controlada (SNCR)" do
  include WebSpecHelpers

  let(:organization) { create_organization }
  let(:doctor) { create_doctor(organization: organization) }
  let(:patient) { create_patient(user: doctor, organization: organization) }

  def render_html(prescription)
    described_class.new(document: prescription.document, base_url: "http://app.prescsign.local").send(:html)
  end

  it "mostra tipo e numeração nacional em receita controlada" do
    SncrNumbering.import_numbers!(doctor_profile: doctor.doctor_profile, sncr_type: "NRB", numbers: [ "2411.1-00.0000001" ])
    prescription = create_prescription_document(user: doctor, patient: patient, organization: organization, sncr_type: "NRB")
    Sncr::NumberingAssignment.ensure_for!(prescription)

    html = render_html(prescription.reload)

    expect(html).to include("Numeração nacional")
    expect(html).to include("2411.1-00.0000001")
    expect(html).to include("NRB")
    expect(html).to include(Prescription::SNCR_TYPE_LABELS["NRB"])
    expect(html).to include("sncr-banner--blue")
  end

  it "colore o badge conforme o tipo (Portaria 344/98)" do
    {
      "NRA" => "sncr-banner--yellow",
      "NRB" => "sncr-banner--blue",
      "NRB2" => "sncr-banner--blue",
      "RCE" => "sncr-banner--neutral",
      "RET" => "sncr-banner--neutral"
    }.each do |type, css_class|
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization, sncr_type: type)
      expect(render_html(prescription)).to include(css_class)
    end
  end

  it "indica pendência quando controlada ainda sem numeração (rascunho)" do
    prescription = create_prescription_document(user: doctor, patient: patient, organization: organization, sncr_type: "NRA")

    html = render_html(prescription)

    expect(html).to include("Numeração nacional")
    expect(html).to include("pendente de assinatura")
  end

  it "não mostra o bloco SNCR em receita comum" do
    prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)

    html = render_html(prescription)

    expect(html).not_to include("Numeração nacional")
    expect(html).not_to include("SNCR / Anvisa")
  end
end
