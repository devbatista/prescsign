require "rails_helper"

RSpec.describe "Admin::Organizations (back-office)", type: :request do
  let(:organization) { create_organization }

  def create_support(organization:)
    user = create_user(organization: organization)
    grant_role(user, "support")
    user
  end

  describe "as a platform admin" do
    let(:admin) { create_admin(organization: create_organization) }

    before do
      sign_in_web(admin)
      use_admin_host!
    end

    it "lists all organizations across tenants" do
      other = create_organization
      other.update!(name: "Clínica Alfa")

      get "/organizations"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Organizações")
      expect(response.body).to include("Clínica Alfa")
    end

    it "filters organizations by search term" do
      create_organization.update!(name: "Hospital Central")
      create_organization.update!(name: "Consultório Beta")

      get "/organizations", params: { q: "Hospital Central" }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Hospital Central")
      expect(response.body).not_to include("Consultório Beta")
    end

    it "filters organizations by status" do
      active_org = create_organization
      active_org.update!(name: "Ativa SA")
      inactive_org = create_organization
      inactive_org.update!(name: "Inativa SA", active: false)

      get "/organizations", params: { status: "inactive" }

      expect(response.body).to include("Inativa SA")
      expect(response.body).not_to include("Ativa SA")
    end

    it "shows an organization with its counts and units" do
      get "/organizations/#{organization.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(organization.name)
      expect(response.body).to include("Dados cadastrais")
      expect(response.body).to include("Unidades")
    end

    it "deactivates and reactivates an organization" do
      patch "/organizations/#{organization.id}/deactivate"
      expect(response).to redirect_to("/organizations/#{organization.id}")
      expect(organization.reload.active).to be(false)

      patch "/organizations/#{organization.id}/activate"
      expect(organization.reload.active).to be(true)
    end
  end

  describe "as platform support (read-only)" do
    let(:support) { create_support(organization: create_organization) }

    before do
      sign_in_web(support)
      use_admin_host!
    end

    it "can list and view organizations" do
      get "/organizations"
      expect(response).to have_http_status(:ok)

      get "/organizations/#{organization.id}"
      expect(response).to have_http_status(:ok)
    end

    it "cannot deactivate an organization (write restricted to admin)" do
      patch "/organizations/#{organization.id}/deactivate"

      expect(response).to have_http_status(:forbidden)
      expect(organization.reload.active).to be(true)
    end
  end

  describe "as a non-platform user" do
    let(:responsible) { create_org_responsible(organization: organization) }

    before do
      sign_in_web(responsible)
      use_admin_host!
    end

    it "is redirected out of the back-office" do
      get "/organizations"
      expect(response).to have_http_status(:found)
    end
  end
end
