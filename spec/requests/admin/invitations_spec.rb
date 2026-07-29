require "rails_helper"

RSpec.describe "Admin::Invitations (back-office)", type: :request do
  let(:organization) { create_organization }

  def create_support(organization:)
    user = create_user(organization: organization)
    grant_role(user, "support")
    user
  end

  def issue_invitation(email: "convidado.#{SecureRandom.hex(3)}@example.com", organization: create_organization)
    invitation, = OrganizationRegistrationInvitation.issue!(organization: organization, invited_email: email)
    invitation
  end

  describe "as a platform admin" do
    let(:admin) { create_admin(organization: create_organization) }

    before do
      sign_in_web(admin)
      use_admin_host!
    end

    it "lists invitations across tenants with their status" do
      issue_invitation(email: "pendente@example.com")

      get "/invitations"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Convites de cadastro")
      expect(response.body).to include("pendente@example.com")
      expect(response.body).to include("Pendente")
    end

    it "filters invitations by status" do
      pending = issue_invitation(email: "ativo@example.com")
      expired = issue_invitation(email: "vencido@example.com")
      expired.update!(expires_at: 1.day.ago)

      get "/invitations", params: { status: "expired" }

      expect(response.body).to include("vencido@example.com")
      expect(response.body).not_to include("ativo@example.com")
    end

    it "resends an invitation (new token) and supersedes the previous one" do
      invitation = issue_invitation(email: "reenviar@example.com", organization: organization)

      expect {
        post "/invitations/#{invitation.id}/resend"
      }.to change(OrganizationRegistrationInvitation, :count).by(1)
        .and change { ActionMailer::Base.deliveries.size }.by(1)

      expect(response).to have_http_status(:found)
      expect(invitation.reload.expired?).to be(true)
      newest = OrganizationRegistrationInvitation.where(invited_email: "reenviar@example.com").order(:created_at).last
      expect(newest).not_to eq(invitation)
      expect(OrganizationRegistrationInvitation.pending).to include(newest)
    end

    it "revokes a pending invitation by expiring it" do
      invitation = issue_invitation(email: "revogar@example.com", organization: organization)

      patch "/invitations/#{invitation.id}/revoke"

      expect(response).to have_http_status(:found)
      expect(invitation.reload.expired?).to be(true)
      expect(OrganizationRegistrationInvitation.pending).not_to include(invitation)
    end

    it "does not revoke an already accepted invitation" do
      invitation = issue_invitation(email: "aceito@example.com", organization: organization)
      invitation.update!(accepted_at: Time.current)

      patch "/invitations/#{invitation.id}/revoke"

      expect(response).to redirect_to(%r{/invitations})
      follow_redirect!
      expect(response.body).to include("já foi aceito")
    end
  end

  describe "as platform support (read-only)" do
    let(:support) { create_support(organization: create_organization) }

    before do
      sign_in_web(support)
      use_admin_host!
    end

    it "can list invitations" do
      issue_invitation
      get "/invitations"
      expect(response).to have_http_status(:ok)
    end

    it "cannot resend or revoke (write restricted to admin)" do
      invitation = issue_invitation(organization: organization)

      post "/invitations/#{invitation.id}/resend"
      expect(response).to have_http_status(:forbidden)

      patch "/invitations/#{invitation.id}/revoke"
      expect(response).to have_http_status(:forbidden)
      expect(invitation.reload.expired?).to be(false)
    end
  end

  describe "as a non-platform user" do
    let(:responsible) { create_org_responsible(organization: organization) }

    before do
      sign_in_web(responsible)
      use_admin_host!
    end

    it "is redirected out of the back-office" do
      get "/invitations"
      expect(response).to have_http_status(:found)
    end
  end
end
