require "rails_helper"

RSpec.describe "App::Doctors", type: :request do
  let(:organization) { create_organization }

  describe "as organization responsible" do
    let(:user) { create_org_responsible(organization: organization) }

    before do
      sign_in_web(user)
      use_app_host!
    end

    it "lists active doctors of the organization" do
      get "/doctors"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Médicos Ativos")
    end

    it "paginates the doctors table" do
      21.times do |index|
        doctor = create_doctor(organization: organization)
        doctor.doctor_profile.update!(full_name: format("Dra Página %02d", index + 1))
      end

      get "/doctors"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Página 1 de 2 · 21 no total")
      expect(response.body).to include("Dra Página 20")
      expect(response.body).not_to include("Dra Página 21")

      get "/doctors", params: { page: 2 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Página 2 de 2 · 21 no total")
      expect(response.body).to include("Dra Página 21")
    end

    it "renders the direct-creation form" do
      get "/doctors/new"
      expect(response).to have_http_status(:ok)
      expect(nav_link_for("/doctors")["class"]).to include("bg-ps-info-bg")
      expect(response.body).to include("Cadastrar Médico").and include("Especialidades")
      expect(response.body.scan("doctor_profile[doctor_specialties_attributes][0][specialty_name]").size).to eq(1)
      expect(response.body).to include("Adicionar especialidade")
      expect(response.body).not_to include("doctor_profile[doctor_specialties_attributes][1][specialty_name]")
    end

    it "creates a doctor with specialties and emails a password-setup link" do
      specialty_name = "Especialidade Teste Rename"

      expect {
        post "/doctors", params: {
          email: "novo.medico@example.com",
          doctor_profile: {
            full_name: "Dr. Novo Médico",
            cpf: "39053344705",
            license_number: "CRM99999", license_state: "SP", gender: "male",
            doctor_specialties_attributes: {
              "0" => { specialty_name: specialty_name, rqe_number: "RQE-9" },
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
      expect(created_user.doctor_profile.specialty_names).to eq([specialty_name])
      expect(created_user.doctor_profile.doctor_specialties.first.rqe_number).to eq("RQE-9")
    end

    it "reuses an existing specialty (case-insensitive) instead of duplicating" do
      Specialty.find_or_create_by!(name: "Cardiologia")

      expect {
        post "/doctors", params: {
          email: "outro.medico@example.com",
          doctor_profile: {
            full_name: "Dra. Outra Médica",
            cpf: "28506973072",
            license_number: "CRM88888", license_state: "SP",
            doctor_specialties_attributes: { "0" => { specialty_name: "cardiologia" } }
          }
        }
      }.to change(DoctorProfile, :count).by(1).and change(Specialty, :count).by(0)
    end

    it "shows a clear error when CRM already exists in the organization" do
      existing_doctor = create_doctor(organization: organization)
      existing_profile = existing_doctor.doctor_profile

      expect {
        post "/doctors", params: {
          email: "crm.repetido@example.com",
          doctor_profile: {
            full_name: "Dr. CRM Repetido",
            cpf: "15350946056",
            license_number: existing_profile.license_number,
            license_state: existing_profile.license_state
          }
        }
      }.not_to change(DoctorProfile, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("CRM já existe para esta clínica.")
    end

    it "allows the same CRM in another organization" do
      other_organization = create_organization
      existing_doctor = create_doctor(organization: other_organization)
      existing_profile = existing_doctor.doctor_profile

      expect {
        post "/doctors", params: {
          email: "crm.outra.clinica@example.com",
          doctor_profile: {
            full_name: "Dra. Outra Clínica",
            cpf: "24614737020",
            license_number: existing_profile.license_number,
            license_state: existing_profile.license_state
          }
        }
      }.to change(DoctorProfile, :count).by(1)

      expect(response).to have_http_status(:found)
    end

    it "links an existing doctor by email instead of creating a duplicate" do
      other_organization = create_organization
      existing_doctor = create_doctor(organization: other_organization)
      existing_profile = existing_doctor.doctor_profile

      expect {
        post "/doctors", params: {
          email: existing_doctor.email,
          doctor_profile: {
            full_name: existing_profile.full_name,
            cpf: existing_profile.cpf,
            license_number: existing_profile.license_number,
            license_state: existing_profile.license_state
          }
        }
      }.to change(OrganizationMembership, :count).by(1)
        .and change(User, :count).by(0)
        .and change(DoctorProfile, :count).by(0)

      expect(response).to have_http_status(:found)
      expect(flash[:notice]).to eq("Médico vinculado a esta clínica.")
      expect(existing_doctor.membership_for(organization.id)&.role).to eq("doctor")
    end

    it "links an existing doctor by CPF instead of creating a duplicate" do
      other_organization = create_organization
      existing_doctor = create_doctor(organization: other_organization)
      existing_profile = existing_doctor.doctor_profile

      expect {
        post "/doctors", params: {
          email: "novo.email.para.medico@example.com",
          doctor_profile: {
            full_name: existing_profile.full_name,
            cpf: existing_profile.cpf,
            license_number: existing_profile.license_number,
            license_state: existing_profile.license_state
          }
        }
      }.to change(OrganizationMembership, :count).by(1)
        .and change(User, :count).by(0)
        .and change(DoctorProfile, :count).by(0)

      expect(response).to have_http_status(:found)
      expect(existing_doctor.membership_for(organization.id)&.role).to eq("doctor")
    end

    it "rejects linking when email and CPF belong to different doctors" do
      email_doctor = create_doctor(organization: create_organization)
      cpf_doctor = create_doctor(organization: create_organization)

      expect {
        post "/doctors", params: {
          email: email_doctor.email,
          doctor_profile: {
            full_name: email_doctor.doctor_profile.full_name,
            cpf: cpf_doctor.doctor_profile.cpf,
            license_number: email_doctor.doctor_profile.license_number,
            license_state: email_doctor.doctor_profile.license_state
          }
        }
      }.not_to change(OrganizationMembership, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("E-mail e CPF pertencem a médicos diferentes.")
    end

    it "re-renders with 422 on invalid data (missing name)" do
      post "/doctors", params: {
        email: "",
        doctor_profile: { full_name: "", license_number: "", license_state: "" }
      }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "as doctor (forbidden)" do
    let(:doctor) { create_doctor(organization: organization) }

    before do
      sign_in_web(doctor)
      use_app_host!
    end

    it "forbids access to the management screen" do
      get "/doctors"
      expect(response).to have_http_status(:forbidden)
    end
  end
end
