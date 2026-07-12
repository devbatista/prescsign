require "rails_helper"

RSpec.describe "App::Consultations", type: :request do
  let(:organization) { create_organization }
  let(:user) { create_org_responsible(organization: organization) }
  let(:patient) { create_patient(user: user, organization: organization) }

  before do
    sign_in_web(user)
    use_app_host!
  end

  it "requires a patient to list, then lists that patient's consultations" do
    get "/consultations"
    expect(response).to have_http_status(:ok)

    consultation = Consultation.create!(patient: patient, user: user, organization: organization, scheduled_at: 1.day.from_now, status: "scheduled")
    get "/consultations", params: { patient_id: patient.id }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(consultation.chief_complaint.to_s.presence || patient.full_name)
  end

  it "creates a consultation" do
    expect {
      post "/consultations", params: { consultation: {
        patient_id: patient.id, scheduled_at: 1.day.from_now.change(min: 0).strftime("%Y-%m-%dT%H:%M"),
        chief_complaint: "Dor"
      } }
    }.to change(Consultation, :count).by(1)
    expect(response).to have_http_status(:found)
  end

  it "cancels a consultation" do
    consultation = Consultation.create!(patient: patient, user: user, organization: organization, scheduled_at: 1.day.from_now, status: "scheduled")
    patch "/consultations/#{consultation.id}/cancel"
    expect(response).to have_http_status(:found)
    expect(consultation.reload.status).to eq("cancelled")
  end

  it "returns 404 for a consultation from another organization" do
    other_org = create_organization
    other_user = create_org_responsible(organization: other_org)
    other_patient = create_patient(user: other_user, organization: other_org)
    foreign = Consultation.create!(patient: other_patient, user: other_user, organization: other_org, scheduled_at: 1.day.from_now, status: "scheduled")

    get "/consultations/#{foreign.id}"
    expect(response).to have_http_status(:not_found)
  end
end
