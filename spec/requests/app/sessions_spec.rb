require "rails_helper"

RSpec.describe "App::Sessions (login/logout)", type: :request do
  it "renders the sign-in page on the login subdomain" do
    use_login_host!
    get "/sign-in"
    expect(response).to have_http_status(:ok)
  end

  it "signs in with valid credentials and redirects to the app subdomain" do
    org = create_organization
    user = create_user(organization: org, password: "password123")
    create_membership(user: user, organization: org, role: "owner")

    use_login_host!
    post "/sign-in", params: { user: { email: user.email, password: "password123" } }

    expect(response).to have_http_status(:found)
    expect(response.location).to include("app.prescsign.local")
  end

  it "re-renders sign-in with invalid credentials" do
    org = create_organization
    user = create_user(organization: org, password: "password123")

    use_login_host!
    post "/sign-in", params: { user: { email: user.email, password: "wrong" } }

    expect(response.status).to be_in([401, 422, 200])
    expect(response.location).to be_nil
  end

  it "redirects unauthenticated panel access to the login subdomain" do
    use_app_host!
    get "/patients"
    expect(response).to have_http_status(:found)
    expect(response.location).to include("login.prescsign.local")
  end

  it "signs out from the app subdomain and redirects to login" do
    org = create_organization
    user = create_user(organization: org)
    create_membership(user: user, organization: org, role: "owner")
    sign_in_web(user)

    use_app_host!
    delete "/sign-out"

    expect(response).to have_http_status(:found)
    expect(response.location).to include("login.prescsign.local")
  end
end
