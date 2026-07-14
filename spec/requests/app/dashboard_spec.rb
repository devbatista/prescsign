require "rails_helper"

RSpec.describe "App::Dashboard", type: :request do
  describe "as organization responsible" do
    it "keeps the organization-wide dashboard" do
      organization = create_organization
      owner = create_org_responsible(organization: organization)

      sign_in_web(owner)
      use_app_host!

      get "/"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Indicadores Reais")
      expect(response.body).to include("Pacientes Recentes")
      expect(response.body).to include("Médicos Recentes")
      expect(response.body).not_to include("Minha Atuação")
    end
  end

  describe "as doctor" do
    it "shows only data related to the signed-in doctor" do
      organization = create_organization
      doctor = create_doctor(organization: organization)
      other_doctor = create_doctor(organization: organization)
      patient = create_patient(user: doctor, organization: organization)
      other_patient = create_patient(user: other_doctor, organization: organization)

      Consultation.create!(
        patient: patient,
        user: doctor,
        organization: organization,
        scheduled_at: 1.day.from_now,
        chief_complaint: "Retorno cardiológico"
      )
      Consultation.create!(
        patient: other_patient,
        user: other_doctor,
        organization: organization,
        scheduled_at: 1.day.from_now,
        chief_complaint: "Consulta de terceiro"
      )
      create_prescription_document(user: doctor, patient: patient, organization: organization)
      create_prescription_document(user: other_doctor, patient: other_patient, organization: organization)

      sign_in_web(doctor)
      use_app_host!

      get "/"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Minha Atuação")
      expect(response.body).to include("Minha Agenda")
      expect(response.body).to include("Meus Documentos Recentes")
      expect(response.body).to include(patient.full_name)
      expect(response.body).to include("Retorno cardiológico")
      expect(response.body).not_to include(other_patient.full_name)
      expect(response.body).not_to include("Consulta de terceiro")
      expect(response.body).not_to include("Médicos Recentes")
    end
  end
end
