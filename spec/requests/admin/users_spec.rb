require "rails_helper"

RSpec.describe "Admin::Users (back-office)", type: :request do
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

    it "lists all users with their roles and status" do
      target = create_user(organization: create_organization, email: "alvo@example.com")
      grant_role(target, "manager")

      get "/users"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Usuários &amp; papéis").or include("Usuários & papéis")
      expect(response.body).to include("alvo@example.com")
      expect(response.body).to include("Gerente")
    end

    it "filters users by role" do
      create_user(organization: create_organization, email: "semrole@example.com")
      with_role = create_user(organization: create_organization, email: "gerente@example.com")
      grant_role(with_role, "manager")

      get "/users", params: { role: "manager" }

      expect(response.body).to include("gerente@example.com")
      expect(response.body).not_to include("semrole@example.com")
    end

    it "filters users by status" do
      create_user(organization: create_organization, email: "ativo@example.com")
      blocked = create_user(organization: create_organization, email: "bloqueado@example.com")
      blocked.update!(status: "blocked")

      get "/users", params: { status: "blocked" }

      expect(response.body).to include("bloqueado@example.com")
      expect(response.body).not_to include("ativo@example.com")
    end

    it "shows a user with roles, memberships and doctor profile" do
      target = create_doctor(organization: create_organization)

      get "/users/#{target.id}"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(target.email)
      expect(response.body).to include("Papéis de plataforma")
      expect(response.body).to include("Perfil médico")
    end

    it "grants and revokes a platform role" do
      target = create_user(organization: create_organization)

      post "/users/#{target.id}/grant_role", params: { role: "support" }
      expect(response).to redirect_to("/users/#{target.id}")
      expect(target.reload.has_role?("support")).to be(true)

      delete "/users/#{target.id}/revoke_role", params: { role: "support" }
      expect(target.reload.has_role?("support")).to be(false)
    end

    it "rejects granting a non-manageable role (super_admin)" do
      target = create_user(organization: create_organization)

      post "/users/#{target.id}/grant_role", params: { role: "super_admin" }

      expect(target.reload.has_role?("super_admin")).to be(false)
      follow_redirect!
      expect(response.body).to include("não gerenciável")
    end

    it "blocks and reactivates a user" do
      target = create_user(organization: create_organization)

      patch "/users/#{target.id}/block"
      expect(target.reload.status).to eq("blocked")

      patch "/users/#{target.id}/activate"
      expect(target.reload.status).to eq("active")
    end

    it "does not let an admin change their own roles or status" do
      patch "/users/#{admin.id}/block"

      expect(admin.reload.status).to eq("active")
      follow_redirect!
      expect(response.body).to include("não pode alterar seus próprios")
    end

    it "does not let a regular admin manage a super_admin" do
      target = create_user(organization: create_organization)
      grant_role(target, "super_admin")

      post "/users/#{target.id}/grant_role", params: { role: "support" }

      expect(target.reload.has_role?("support")).to be(false)
      follow_redirect!
      expect(response.body).to include("super admin")
    end
  end

  describe "as platform support (read-only)" do
    let(:support) { create_support(organization: create_organization) }

    before do
      sign_in_web(support)
      use_admin_host!
    end

    it "can list and view users" do
      target = create_user(organization: create_organization)
      get "/users"
      expect(response).to have_http_status(:ok)
      get "/users/#{target.id}"
      expect(response).to have_http_status(:ok)
    end

    it "cannot grant roles or block (write restricted to admin)" do
      target = create_user(organization: create_organization)

      post "/users/#{target.id}/grant_role", params: { role: "support" }
      expect(response).to have_http_status(:forbidden)

      patch "/users/#{target.id}/block"
      expect(response).to have_http_status(:forbidden)
      expect(target.reload.status).to eq("active")
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
      get "/users"
      expect(response).to have_http_status(:found)
    end
  end
end
