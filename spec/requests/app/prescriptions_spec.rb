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

  it "renders the new form with the medications datalist" do
    create_medication(name: "Dipirona", strength: "500 mg", active_ingredient: "Dipirona monoidratada")

    get "/prescriptions/new", params: { patient_id: patient.id }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('id="medications-list"')
    expect(response.body).to include("Dipirona 500 mg")
    expect(response.body).to include("Adicionar medicamento")
  end

  it "creates a prescription from structured items and synthesizes content" do
    medication = create_medication(name: "Dipirona", strength: "500 mg")

    expect {
      post "/prescriptions", params: { prescription: {
        patient_id: patient.id, issued_on: Date.current.iso8601, content: "",
        prescription_items_attributes: {
          "0" => { name: "Dipirona", strength: "500 mg", quantity: "1 caixa",
                   posology: "1 cp de 6/6h", medication_id: medication.id },
          "1" => { name: "Losartana", strength: "50 mg" }
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
