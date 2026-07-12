require "rails_helper"

RSpec.describe "App::Profile (me)", type: :request do
  let(:organization) { create_organization }

  describe "as doctor" do
    let(:doctor) { create_doctor(organization: organization) }

    before do
      sign_in_web(doctor)
      use_app_host!
    end

    it "shows the professional profile" do
      get "/profile"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Dados Profissionais")
    end

    it "renders the edit form and updates the profile" do
      get "/profile/edit"
      expect(response).to have_http_status(:ok)

      patch "/profile", params: { doctor: {
        full_name: doctor.doctor_profile.full_name,
        license_number: doctor.doctor_profile.license_number,
        license_state: "RJ", email: doctor.email,
        doctor_specialties_attributes: { "0" => { specialty_name: "Dermatologia", rqe_number: "RQE-7" } }
      } }
      expect(response).to have_http_status(:found)
      expect(doctor.doctor_profile.reload.specialty_names).to include("Dermatologia")
      expect(doctor.doctor_profile.license_state).to eq("RJ")
    end
  end

  describe "as non-doctor" do
    let(:user) { create_org_responsible(organization: organization) }

    before do
      sign_in_web(user)
      use_app_host!
    end

    it "shows an empty state (no professional profile)" do
      get "/profile"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("não possui um perfil profissional")
    end
  end
end
