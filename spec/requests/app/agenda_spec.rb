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
    specialty = create_specialty
    Consultation.create!(patient: patient, user: user, organization: organization,
                         specialty: specialty, scheduled_at: Date.current.to_time.change(hour: 10),
                         status: "scheduled")
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

  it "details only the selected day when a calendar day is clicked" do
    specialty = create_specialty
    selected_day = Date.current.beginning_of_month + 5.days
    other_day = selected_day + 1.day
    selected_patient = create_patient(user: user, organization: organization)
    other_patient = create_patient(user: user, organization: organization)

    Consultation.create!(
      patient: selected_patient,
      user: user,
      organization: organization,
      specialty: specialty,
      scheduled_at: selected_day.to_time.change(hour: 9),
      status: "scheduled"
    )
    Consultation.create!(
      patient: other_patient,
      user: user,
      organization: organization,
      specialty: specialty,
      scheduled_at: other_day.to_time.change(hour: 10),
      status: "scheduled"
    )

    get "/agenda", params: { month: selected_day.strftime("%Y-%m"), day: selected_day.iso8601 }

    expect(response).to have_http_status(:ok)
    details = Nokogiri::HTML(response.body).at_css("[data-selected-day-details]").text
    expect(details).to include(selected_day.strftime("%d/%m/%Y"))
    expect(details).to include(selected_patient.full_name)
    expect(details).not_to include(other_patient.full_name)
  end

  it "redirects unauthenticated access to login" do
    sign_out :user
    get "/agenda"
    expect(response).to have_http_status(:found)
    expect(response.location).to include("login.prescsign.local")
  end
end
