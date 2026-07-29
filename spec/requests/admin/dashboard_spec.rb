require "rails_helper"

RSpec.describe "Admin::Dashboard (back-office)", type: :request do
  describe "as a platform admin" do
    let(:admin) { create_admin(organization: create_organization) }

    before do
      sign_in_web(admin)
      use_admin_host!
    end

    it "renders the back-office dashboard with the organizations module link" do
      get "/"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Back-office")
      expect(response.body).to include("Organizações")
      expect(response.body).to include('href="/organizations"')
    end
  end

  describe "as a non-platform user" do
    let(:organization) { create_organization }
    let(:responsible) { create_org_responsible(organization: organization) }

    before do
      sign_in_web(responsible)
      use_admin_host!
    end

    it "is redirected out of the back-office" do
      get "/"
      expect(response).to have_http_status(:found)
    end
  end
end
