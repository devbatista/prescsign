require "rails_helper"

RSpec.describe "App::Organizations (creation)", type: :request do
  let(:organization) { create_organization }
  let(:admin) { create_admin(organization: organization) }

  before do
    sign_in_web(admin)
    use_app_host!
  end

  it "renders the new organization form" do
    get "/organizations/new"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Nova Organização")
  end

  it "creates an organization with owner membership and responsible invitation" do
    expect {
      post "/organizations", params: { organization: {
        name: "Clinica Nova", kind: "clinica", legal_name: "Clinica Nova LTDA",
        cnpj: SecureRandom.random_number(10**14).to_s.rjust(14, "0"),
        email: "clinica.#{SecureRandom.hex(3)}@example.com",
        responsible_email: "resp@example.com", state: "SP", country: "BR"
      } }
    }.to change(Organization, :count).by(1)
      .and change(OrganizationRegistrationInvitation, :count).by(1)

    expect(response).to have_http_status(:found)
    new_org = Organization.order(:created_at).last
    membership = admin.organization_memberships.find_by(organization_id: new_org.id)
    expect(membership.role).to eq("owner")
    expect(membership.status).to eq("active")
  end

  it "re-renders with an error when the responsible email is missing" do
    post "/organizations", params: { organization: {
      name: "Sem Responsavel", kind: "autonomo", responsible_email: ""
    } }
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
