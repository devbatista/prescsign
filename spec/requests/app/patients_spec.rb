require "rails_helper"

RSpec.describe "App::Patients", type: :request do
  let(:organization) { create_organization }
  let(:user) { create_org_responsible(organization: organization) }

  before do
    sign_in_web(user)
    use_app_host!
  end

  it "lists patients" do
    patient = create_patient(user: user, organization: organization)
    get "/patients"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(patient.full_name)
  end

  it "renders the new form and creates a patient" do
    get "/patients/new"
    expect(response).to have_http_status(:ok)

    expect {
      post "/patients", params: { patient: {
        full_name: "João da Silva", cpf: "39053344705", birth_date: "1990-01-01"
      } }
    }.to change(Patient, :count).by(1)
    expect(response).to have_http_status(:found)
  end

  it "re-renders new with errors on invalid data" do
    post "/patients", params: { patient: { full_name: "", cpf: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "updates a patient" do
    patient = create_patient(user: user, organization: organization)
    patch "/patients/#{patient.id}", params: { patient: { full_name: "Nome Novo" } }
    expect(response).to have_http_status(:found)
    expect(patient.reload.full_name).to eq("Nome Novo")
  end

  it "soft-inactivates a patient on destroy" do
    patient = create_patient(user: user, organization: organization)
    delete "/patients/#{patient.id}"
    expect(response).to have_http_status(:found)
    expect(patient.reload.active).to be(false)
  end

  it "shows a consultations area with the scheduling form" do
    patient = create_patient(user: user, organization: organization)
    consultation = Consultation.create!(
      patient: patient, user: user, organization: organization,
      scheduled_at: 1.day.from_now, chief_complaint: "Dor de cabeça"
    )

    get "/patients/#{patient.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Consultas")
    expect(response.body).to include("Agendar")
    expect(response.body).to include("Especialista")
    expect(response.body).to include("Dor de cabeça")
    expect(response.body).to include(consultation_path(consultation))
  end

  it "schedules a consultation from the patient page with an optional specialist" do
    patient = create_patient(user: user, organization: organization)
    doctor = create_doctor(organization: organization)

    expect {
      post "/consultations", params: {
        patient_id: patient.id,
        consultation: { patient_id: patient.id, scheduled_at: 2.days.from_now, user_id: doctor.id }
      }
    }.to change { patient.consultations.count }.by(1)

    expect(response).to have_http_status(:found)
    expect(patient.consultations.last.user).to eq(doctor)
  end

  it "forces doctors to schedule consultations for themselves" do
    doctor = create_doctor(organization: organization)
    other_doctor = create_doctor(organization: organization)
    patient = create_patient(user: doctor, organization: organization)
    sign_in_web(doctor)

    expect {
      post "/consultations", params: {
        patient_id: patient.id,
        consultation: { patient_id: patient.id, scheduled_at: 2.days.from_now, user_id: other_doctor.id }
      }
    }.to change { patient.consultations.count }.by(1)

    expect(response).to have_http_status(:found)
    expect(patient.consultations.last.user).to eq(doctor)
  end

  it "does not show specialist selection to doctors" do
    doctor = create_doctor(organization: organization)
    patient = create_patient(user: doctor, organization: organization)
    sign_in_web(doctor)

    get "/patients/#{patient.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Especialista")
  end

  it "defaults the professional to the current user when no specialist is chosen" do
    patient = create_patient(user: user, organization: organization)

    post "/consultations", params: {
      patient_id: patient.id,
      consultation: { patient_id: patient.id, scheduled_at: 2.days.from_now }
    }

    expect(response).to have_http_status(:found)
    expect(patient.consultations.last.user).to eq(user)
  end

  it "does not expose patients from another organization (404)" do
    other_org = create_organization
    other_user = create_org_responsible(organization: other_org)
    foreign = create_patient(user: other_user, organization: other_org)

    get "/patients/#{foreign.id}"
    expect(response).to have_http_status(:not_found)
  end
end
