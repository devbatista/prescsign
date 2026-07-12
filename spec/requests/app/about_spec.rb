require "rails_helper"

RSpec.describe "App::Pages#about", type: :request do
  let(:organization) { create_organization }

  it "is visible to an admin" do
    admin = create_admin(organization: organization)
    sign_in_web(admin)
    use_app_host!

    get "/about"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sobre o PrescSign")
  end

  it "is forbidden for a doctor" do
    doctor = create_doctor(organization: organization)
    sign_in_web(doctor)
    use_app_host!

    get "/about"
    expect(response).to have_http_status(:forbidden)
  end
end
