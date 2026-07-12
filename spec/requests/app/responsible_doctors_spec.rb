require "rails_helper"

RSpec.describe "App::ResponsibleDoctors", type: :request do
  let(:organization) { create_organization }

  describe "as organization responsible" do
    let(:user) { create_org_responsible(organization: organization) }

    before do
      sign_in_web(user)
      use_app_host!
    end

    it "lists doctors and pending invitations" do
      get "/responsible_doctors"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Médicos Ativos").and include("Convites Pendentes")
    end

    it "invites a doctor by email" do
      expect {
        post "/responsible_doctors", params: { invited_email: "novo.medico@example.com" }
      }.to change(OrganizationRegistrationInvitation, :count).by(1)
      expect(response).to have_http_status(:found)
    end

    it "re-renders with an error when email is blank" do
      post "/responsible_doctors", params: { invited_email: "" }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "as doctor (forbidden)" do
    let(:doctor) { create_doctor(organization: organization) }

    before do
      sign_in_web(doctor)
      use_app_host!
    end

    it "forbids access to the management screen" do
      get "/responsible_doctors"
      expect(response).to have_http_status(:forbidden)
    end
  end
end
