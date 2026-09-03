require "rails_helper"

RSpec.describe "App::Prescriptions (structured items + catalog)", type: :request do
  let(:organization) { create_organization }
  let(:doctor) { create_doctor(organization: organization) }
  let(:patient) { create_patient(user: doctor, organization: organization) }

  before do
    specialty = create_specialty
    assign_specialty(doctor: doctor, specialty: specialty)
    Consultation.create!(
      patient: patient, user: doctor, organization: organization, specialty: specialty,
      scheduled_at: 1.day.ago, finished_at: Time.current, status: "completed"
    )
    sign_in_web(doctor)
    use_app_host!
  end

  it "renders the new form with the catalog search field, not the catalog itself" do
    create_medication(name: "Dipirona", strength: "500 mg", active_ingredient: "Dipirona monoidratada")

    get "/prescriptions/new", params: { patient_id: patient.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("data-medication-search-url=\"/medications/search\"")
    expect(response.body).to include("Adicionar medicamento")
    # O catálogo tem dezenas de milhares de apresentações: não pode vir no HTML.
    expect(response.body).not_to include("Dipirona 500 mg")
  end

  it "creates a prescription from structured items and synthesizes content" do
    medication = create_medication(name: "Dipirona", strength: "500 mg")

    expect {
      post "/prescriptions", params: { prescription: {
        patient_id: patient.id, issued_on: Date.current.iso8601, content: "",
        prescription_items_attributes: {
          "0" => { name: "Dipirona", strength: "500 mg", quantity: "1 caixa",
                   posology: "1 cp de 6/6h", medication_id: medication.id },
          # Item de texto livre precisa dizer de onde sai a classificação; aqui o
          # foco é a síntese do content, então confirma que não é controlado.
          "1" => { name: "Losartana", strength: "50 mg", uncontrolled_confirmed: "1" }
        }
      } }
    }.to change(Prescription, :count).by(1)
      .and change(PrescriptionItem, :count).by(2)
      .and change(Document, :count).by(1)

    expect(response).to have_http_status(:found)
    prescription = Prescription.order(:created_at).last
    expect(prescription.content).to include("1. Dipirona 500 mg — 1 caixa — 1 cp de 6/6h")
    expect(prescription.content).to include("2. Losartana 50 mg")
    expect(prescription.prescription_items.first.medication).to eq(medication)
  end

  it "renders the edit form for a prescription with persisted items" do
    prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
    prescription.prescription_items.create!(name: "Dipirona", strength: "500 mg")

    get "/prescriptions/#{prescription.id}/edit"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Dipirona")
    expect(response.body).to include("Remover este item")
  end

  describe "tipo de receita controlada no formulário" do
    def sncr_field
      Nokogiri::HTML(response.body).at_css("[data-sncr-field]")
    end

    it "mostra receita comum, sem campo editável, quando não há item de onde derivar" do
      get "/prescriptions/new", params: { patient_id: patient.id }

      field = sncr_field
      expect(field.at_css("[data-sncr-common]")["class"].to_s).not_to include("hidden")
      expect(field.at_css("[data-sncr-derived]")["class"]).to include("hidden")
      # Quem manipula o tipo é o medicamento: não há campo para o médico mexer.
      expect(field.at_css("select, input")).to be_nil
    end

    it "deriva o tipo do item controlado" do
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
      prescription.prescription_items.create!(name: "Clonazepam", strength: "2 mg", sncr_type: "NRB")

      get "/prescriptions/#{prescription.id}/edit"

      field = sncr_field
      expect(field.at_css("[data-sncr-derived]")["class"]).not_to include("hidden")
      expect(field.at_css("[data-sncr-derived-text]").text).to include("NRB — #{Prescription::SNCR_TYPE_LABELS['NRB']}")
      expect(field.at_css("[data-sncr-common]")["class"]).to include("hidden")
      expect(field.at_css("select, input")).to be_nil
    end

    it "ignora um tipo enviado na requisição — quem decide é o medicamento" do
      medication = create_medication(name: "Clonazepam", strength: "2 mg")
      medication.substances << Substance.create!(name: "clonazepam", list_344: "B1", sncr_type: "NRB")

      post "/prescriptions", params: { prescription: {
        patient_id: patient.id, issued_on: Date.current.iso8601, content: "", sncr_type: "NRA",
        prescription_items_attributes: {
          "0" => { name: "Clonazepam", strength: "2 mg", medication_id: medication.id }
        }
      } }

      expect(Prescription.order(:created_at).last.sncr_type).to eq("NRB")
    end

    it "não deixa a requisição tornar controlada uma receita sem item controlado" do
      post "/prescriptions", params: { prescription: {
        patient_id: patient.id, issued_on: Date.current.iso8601, content: "Repouso e hidratação.",
        sncr_type: "NRB"
      } }

      expect(Prescription.order(:created_at).last.sncr_type).to be_nil
    end

    it "avisa quando os itens exigem receituários diferentes" do
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
      prescription.prescription_items.create!(name: "Clonazepam", sncr_type: "NRB")
      prescription.prescription_items.create!(name: "Morfina", sncr_type: "NRA")

      get "/prescriptions/#{prescription.id}/edit"

      field = sncr_field
      expect(field.at_css("[data-sncr-conflict]")["class"]).not_to include("hidden")
      expect(field.at_css("[data-sncr-conflict-text]").text).to include("NRB, NRA")
      expect(field.at_css("[data-sncr-derived]")["class"]).to include("hidden")
      expect(field.at_css("[data-sncr-common]")["class"]).to include("hidden")
    end

    it "leva o tipo de cada item para o card, para o formulário derivar sem ida ao servidor" do
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
      prescription.prescription_items.create!(name: "Clonazepam", sncr_type: "NRB")

      get "/prescriptions/#{prescription.id}/edit"

      card = Nokogiri::HTML(response.body).at_css("[data-prescription-item-card]")
      expect(card["data-sncr-type"]).to eq("NRB")
    end
  end

  it "revokes a prescription when a reason is given and records it in the audit log" do
    prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)

    patch "/prescriptions/#{prescription.id}/revoke", params: { reason: "Erro de dosagem" }

    expect(response).to have_http_status(:found)
    expect(prescription.reload.status).to eq("cancelled")
    expect(prescription.document.reload.status).to eq("revoked")
    revoked_log = AuditLog.where(action: "revoked").order(:created_at).last
    expect(revoked_log.after_data["reason"]).to eq("Erro de dosagem")
  end

  it "refuses to revoke without a reason and keeps the document intact" do
    prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)

    patch "/prescriptions/#{prescription.id}/revoke", params: { reason: "   " }

    expect(response).to redirect_to(document_path(prescription.document))
    expect(flash[:alert]).to eq("Informe o motivo da revogação.")
    expect(prescription.reload.status).to eq("draft")
    expect(prescription.document.reload.status).not_to eq("revoked")
    expect(AuditLog.where(action: "revoked")).to be_empty
  end

  it "still supports free-text prescriptions without items" do
    expect {
      post "/prescriptions", params: { prescription: {
        patient_id: patient.id, issued_on: Date.current.iso8601, content: "Repouso e hidratação"
      } }
    }.to change(Prescription, :count).by(1)

    prescription = Prescription.order(:created_at).last
    expect(prescription.content).to eq("Repouso e hidratação")
    expect(prescription.prescription_items).to be_empty
  end
end
