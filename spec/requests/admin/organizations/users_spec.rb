require "rails_helper"

RSpec.describe "Admin::Organizations::Users (back-office)", type: :request do
  let(:organization) { create_organization }

  def member(role:, status: "active", email: nil)
    user = create_user(organization: organization, email: email)
    create_membership(user: user, organization: organization, role: role)
    OrganizationMembership.find_by(user: user, organization: organization).update!(status: status)
    user
  end

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

    it "lists the organization members with their org roles" do
      member(role: "doctor", email: "medico@example.com")

      get "/organizations/#{organization.id}/users"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Usuários da organização")
      expect(response.body).to include("medico@example.com")
    end

    it "updates a member's organization role" do
      user = member(role: "staff")

      patch "/organizations/#{organization.id}/users/#{user.id}/update_role", params: { role: "doctor" }

      expect(response).to redirect_to("/organizations/#{organization.id}/users")
      membership = OrganizationMembership.find_by(user: user, organization: organization)
      expect(membership.role).to eq("doctor")
    end

    it "rejects an invalid organization role (admin is platform-only)" do
      user = member(role: "staff")

      patch "/organizations/#{organization.id}/users/#{user.id}/update_role", params: { role: "admin" }

      expect(OrganizationMembership.find_by(user: user, organization: organization).role).to eq("staff")
      follow_redirect!
      expect(response.body).to include("Papel de organização inválido")
    end

    it "deactivates and reactivates a membership" do
      user = member(role: "doctor")

      patch "/organizations/#{organization.id}/users/#{user.id}/deactivate"
      expect(OrganizationMembership.find_by(user: user, organization: organization).status).to eq("inactive")

      patch "/organizations/#{organization.id}/users/#{user.id}/activate"
      expect(OrganizationMembership.find_by(user: user, organization: organization).status).to eq("active")
    end

    it "removes a member and clears their current organization pointer" do
      user = member(role: "doctor")
      user.update!(current_organization_id: organization.id)

      expect {
        delete "/organizations/#{organization.id}/users/#{user.id}/remove"
      }.to change { OrganizationMembership.where(organization: organization).count }.by(-1)

      expect(user.reload.current_organization_id).to be_nil
    end

    it "protects the only active owner from removal, deactivation and demotion" do
      owner = member(role: "owner")

      delete "/organizations/#{organization.id}/users/#{owner.id}/remove"
      expect(OrganizationMembership.find_by(user: owner, organization: organization)).to be_present

      patch "/organizations/#{organization.id}/users/#{owner.id}/deactivate"
      expect(OrganizationMembership.find_by(user: owner, organization: organization).status).to eq("active")

      patch "/organizations/#{organization.id}/users/#{owner.id}/update_role", params: { role: "staff" }
      expect(OrganizationMembership.find_by(user: owner, organization: organization).role).to eq("owner")
    end

    it "allows removing an owner when another active owner remains" do
      owner_a = member(role: "owner", email: "owner-a@example.com")
      member(role: "owner", email: "owner-b@example.com")

      delete "/organizations/#{organization.id}/users/#{owner_a.id}/remove"

      expect(OrganizationMembership.find_by(user: owner_a, organization: organization)).to be_nil
    end
  end

  describe "as platform support (read-only)" do
    let(:support) { create_support(organization: create_organization) }

    before do
      sign_in_web(support)
      use_admin_host!
    end

    it "can list members" do
      member(role: "doctor")
      get "/organizations/#{organization.id}/users"
      expect(response).to have_http_status(:ok)
    end

    it "cannot change a membership (write restricted to admin)" do
      user = member(role: "staff")

      patch "/organizations/#{organization.id}/users/#{user.id}/update_role", params: { role: "doctor" }

      expect(response).to have_http_status(:forbidden)
      expect(OrganizationMembership.find_by(user: user, organization: organization).role).to eq("staff")
    end
  end

  describe "as a non-platform user" do
    let(:responsible) { create_org_responsible(organization: organization) }

    before do
      sign_in_web(responsible)
      use_admin_host!
    end

    it "is redirected out of the back-office" do
      get "/organizations/#{organization.id}/users"
      expect(response).to have_http_status(:found)
    end
  end
end
