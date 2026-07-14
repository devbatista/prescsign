require "rails_helper"

RSpec.describe "App::Agenda", type: :request do
  let(:organization) { create_organization }
  let(:user) { create_org_responsible(organization: organization) }

  before do
    sign_in_web(user)
    use_app_host!
  end

  it "renders the month calendar" do
    get "/agenda"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Calendário de Atendimentos")
  end

  it "shows an event for the current month" do
    patient = create_patient(user: user, organization: organization)
    Consultation.create!(patient: patient, user: user, organization: organization,
                         scheduled_at: Date.current.to_time.change(hour: 10), status: "scheduled")
    get "/agenda", params: { month: Date.current.strftime("%Y-%m") }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(patient.full_name)
  end

  it "shows an event scheduled only by specialty" do
    patient = create_patient(user: user, organization: organization)
    Consultation.create!(
      patient: patient,
      organization: organization,
      specialty: create_specialty,
      scheduled_at: Date.current.to_time.change(hour: 11),
      status: "scheduled"
    )

    get "/agenda", params: { month: Date.current.strftime("%Y-%m") }

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(patient.full_name)
  end

  it "redirects unauthenticated access to login" do
    sign_out :user
    get "/agenda"
    expect(response).to have_http_status(:found)
    expect(response.location).to include("login.prescsign.local")
  end
end
