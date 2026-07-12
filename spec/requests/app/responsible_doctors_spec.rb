require "rails_helper"

RSpec.describe "App::ResponsibleDoctors", type: :request do
  let(:organization) { create_organization }

  describe "as organization responsible" do
    let(:user) { create_org_responsible(organization: organization) }

    before do
      sign_in_web(user)
      use_app_host!
    end

    it "lists active doctors of the organization" do
      get "/responsible_doctors"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Médicos Ativos")
    end

    it "renders the direct-creation form" do
      get "/responsible_doctors/new"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Cadastrar Médico").and include("Especialidades")
    end

    it "creates a doctor with specialties and emails a password-setup link" do
      expect {
        post "/responsible_doctors", params: {
          email: "novo.medico@example.com",
          doctor_profile: {
            full_name: "Dr. Novo Médico",
            license_number: "CRM99999", license_state: "SP", gender: "male",
            doctor_specialties_attributes: {
              "0" => { specialty_name: "Cardiologia", rqe_number: "RQE-9" },
              "1" => { specialty_name: "", rqe_number: "" }
            }
          }
        }
      }.to change(DoctorProfile, :count).by(1)
        .and change(User, :count).by(1)
        .and change(Specialty, :count).by(1)
        .and change(DoctorSpecialty, :count).by(1)

      expect(response).to have_http_status(:found)

      created_user = User.find_by(email: "novo.medico@example.com")
      expect(created_user).to be_present
      expect(created_user.confirmed_at).to be_nil
      expect(created_user.reset_password_token).to be_present
      expect(created_user.membership_for(organization.id)&.role).to eq("doctor")
      expect(created_user.doctor_profile.specialty_names).to eq(["Cardiologia"])
      expect(created_user.doctor_profile.doctor_specialties.first.rqe_number).to eq("RQE-9")
    end

    it "reuses an existing specialty (case-insensitive) instead of duplicating" do
      Specialty.create!(name: "Cardiologia")

      expect {
        post "/responsible_doctors", params: {
          email: "outro.medico@example.com",
          doctor_profile: {
            full_name: "Dra. Outra Médica",
            license_number: "CRM88888", license_state: "SP",
            doctor_specialties_attributes: { "0" => { specialty_name: "cardiologia" } }
          }
        }
      }.to change(DoctorProfile, :count).by(1).and change(Specialty, :count).by(0)
    end

    it "re-renders with 422 on invalid data (missing name)" do
      post "/responsible_doctors", params: {
        email: "",
        doctor_profile: { full_name: "", license_number: "", license_state: "" }
      }
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
