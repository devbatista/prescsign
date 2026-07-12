require "rails_helper"

RSpec.describe "App::AuditLogs", type: :request do
  let(:organization) { create_organization }
  let(:user) { create_org_responsible(organization: organization) }

  before do
    sign_in_web(user)
    use_app_host!
  end

  it "shows a prompt when no filter is given" do
    get "/audit_logs"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("para consultar a trilha")
  end

  it "lists events filtered by patient" do
    patient = create_patient(user: user, organization: organization)
    AuditLog.record!(actor: user, organization: organization, patient: patient,
                     resource: patient, action: "created", occurred_at: Time.current,
                     before_data: {}, after_data: {})

    get "/audit_logs", params: { patient_id: patient.id }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Criado")
  end

  it "redirects unauthenticated access to login" do
    sign_out :user
    get "/audit_logs"
    expect(response).to have_http_status(:found)
    expect(response.location).to include("login.prescsign.local")
  end
end
