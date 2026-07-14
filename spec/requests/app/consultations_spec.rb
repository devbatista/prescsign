require "rails_helper"

RSpec.describe "App::Consultations", type: :request do
  let(:organization) { create_organization }
  let(:user) { create_org_responsible(organization: organization) }
  let(:patient) { create_patient(user: user, organization: organization) }
  let(:specialty) { create_specialty }

  before do
    sign_in_web(user)
    use_app_host!
  end

  it "lists consultations and still supports filtering by patient" do
    consultation = Consultation.create!(
      patient: patient,
      user: user,
      organization: organization,
      specialty: specialty,
      scheduled_at: 1.day.from_now,
      status: "scheduled",
      chief_complaint: "Consulta do paciente"
    )

    get "/consultations"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Consulta do paciente")

    get "/consultations", params: { patient_id: patient.id }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(consultation.patient.full_name)
  end

  it "shows a doctor's own consultations by default with 10 per page" do
    doctor = create_doctor(organization: organization)
    other_doctor = create_doctor(organization: organization)
    assign_specialty(doctor: doctor, specialty: specialty)
    assign_specialty(doctor: other_doctor, specialty: specialty)
    doctor_patient = create_patient(user: doctor, organization: organization)
    other_patient = create_patient(user: other_doctor, organization: organization)

    11.times do |index|
      Consultation.create!(
        patient: doctor_patient,
        user: doctor,
        organization: organization,
        specialty: specialty,
        scheduled_at: (index + 1).days.from_now,
        status: "scheduled",
        chief_complaint: "Consulta própria #{(index + 1).to_s.rjust(2, '0')}"
      )
    end
    Consultation.create!(
      patient: other_patient,
      user: other_doctor,
      organization: organization,
      specialty: specialty,
      scheduled_at: 1.day.from_now,
      status: "scheduled",
      chief_complaint: "Consulta de outro médico"
    )

    sign_in_web(doctor)

    get "/consultations"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Consulta própria 11")
    expect(response.body).to include("Consulta própria 02")
    expect(response.body).not_to include("Consulta própria 01")
    expect(response.body).not_to include("Consulta de outro médico")
    expect(response.body).to include("Página 1 de 2 · 11 no total")
  end

  it "creates a consultation" do
    doctor = create_doctor(organization: organization)
    assign_specialty(doctor: doctor, specialty: specialty)

    expect {
      post "/consultations", params: { consultation: {
        patient_id: patient.id, scheduled_at: 1.day.from_now.change(min: 0).strftime("%Y-%m-%dT%H:%M"),
        specialty_id: specialty.id,
        chief_complaint: "Dor"
      } }
    }.to change(Consultation, :count).by(1)
    expect(response).to have_http_status(:found)
  end

  it "cancels a consultation" do
    consultation = Consultation.create!(
      patient: patient, user: user, organization: organization, specialty: specialty,
      scheduled_at: 1.day.from_now, status: "scheduled"
    )
    patch "/consultations/#{consultation.id}/cancel"
    expect(response).to have_http_status(:found)
    expect(consultation.reload.status).to eq("cancelled")
  end

  it "returns 404 for a consultation from another organization" do
    other_org = create_organization
    other_user = create_org_responsible(organization: other_org)
    other_patient = create_patient(user: other_user, organization: other_org)
    foreign = Consultation.create!(
      patient: other_patient, user: other_user, organization: other_org, specialty: create_specialty(name: "Pediatria"),
      scheduled_at: 1.day.from_now, status: "scheduled"
    )

    get "/consultations/#{foreign.id}"
    expect(response).to have_http_status(:not_found)
  end
end
