require "rails_helper"

RSpec.describe "App::Patients", type: :request do
  let(:organization) { create_organization }
  let(:user) { create_org_responsible(organization: organization) }

  before do
    sign_in_web(user)
    use_app_host!
  end

  it "lists patients" do
    patient = create_patient(user: user, organization: organization)
    get "/patients"
    expect(response).to have_http_status(:ok)
    expect(nav_link_for("/patients")["class"]).to include("bg-ps-info-bg")
    expect(response.body).to include(patient.full_name)
  end

  it "renders the new form and creates a patient" do
    get "/patients/new"
    expect(response).to have_http_status(:ok)
    expect(nav_link_for("/patients")["class"]).to include("bg-ps-info-bg")

    expect {
      post "/patients", params: { patient: {
        full_name: "João da Silva", cpf: "39053344705", birth_date: "1990-01-01"
      } }
    }.to change(Patient, :count).by(1)
    expect(response).to have_http_status(:found)
  end

  it "does not allow a regular doctor to create patients" do
    doctor = create_doctor(organization: organization)
    sign_in_web(doctor)

    get "/patients"
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include("Novo paciente")

    get "/patients/new"
    expect(response).to have_http_status(:forbidden)

    expect {
      post "/patients", params: { patient: {
        full_name: "Paciente Médico", cpf: "39053344705", birth_date: "1990-01-01"
      } }
    }.not_to change(Patient, :count)
    expect(response).to have_http_status(:forbidden)
  end

  it "allows a regular doctor to see patients linked to their consultations" do
    doctor = create_doctor(organization: organization)
    patient = create_patient(user: user, organization: organization)
    patient.update!(email: "paciente.historico@example.com", phone: "11987654321", birth_date: 30.years.ago.to_date)
    unlinked_patient = create_patient(user: user, organization: organization)
    specialty = create_specialty
    assign_specialty(doctor: doctor, specialty: specialty)
    Consultation.create!(
      patient: patient,
      user: doctor,
      organization: organization,
      specialty: specialty,
      scheduled_at: 1.day.ago,
      finished_at: Time.current,
      status: "completed"
    )
    sign_in_web(doctor)

    get "/patients"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(patient.full_name)
    expect(response.body).not_to include(unlinked_patient.full_name)

    get "/patients/#{patient.id}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(patient.full_name)
    expect(response.body).to include("paciente.historico@example.com")
    expect(response.body).to include("11987654321")
    expect(response.body).to include("Idade")
    expect(response.body).to include("30 anos")
    expect(response.body).not_to include("CPF")
    expect(response.body).not_to include("Nascimento")
    expect(response.body).not_to include(patient.cpf)
    expect(response.body).not_to include("Editar")
    expect(response.body).to include("Consultas")

    get "/patients/#{unlinked_patient.id}"
    expect(response).to have_http_status(:not_found)
  end

  it "allows a doctor who is responsible for the organization to create patients" do
    responsible_doctor = create_org_responsible(organization: organization)
    grant_role(responsible_doctor, "doctor")
    create_doctor_profile(user: responsible_doctor)
    sign_in_web(responsible_doctor)

    get "/patients/new"
    expect(response).to have_http_status(:ok)

    expect {
      post "/patients", params: { patient: {
        full_name: "Paciente Responsável", cpf: "28506973072", birth_date: "1990-01-01"
      } }
    }.to change(Patient, :count).by(1)
    expect(response).to have_http_status(:found)
  end

  it "re-renders new with errors on invalid data" do
    post "/patients", params: { patient: { full_name: "", cpf: "" } }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "updates a patient" do
    patient = create_patient(user: user, organization: organization)
    patch "/patients/#{patient.id}", params: { patient: { full_name: "Nome Novo" } }
    expect(response).to have_http_status(:found)
    expect(patient.reload.full_name).to eq("Nome Novo")
  end

  it "soft-inactivates a patient on destroy" do
    patient = create_patient(user: user, organization: organization)
    delete "/patients/#{patient.id}"
    expect(response).to have_http_status(:found)
    expect(patient.reload.active).to be(false)
  end

  it "shows a consultations area with the scheduling form" do
    patient = create_patient(user: user, organization: organization)
    specialty = create_specialty
    consultation = Consultation.create!(
      patient: patient, user: user, organization: organization, specialty: specialty,
      scheduled_at: 1.day.from_now, chief_complaint: "Dor de cabeça"
    )

    get "/patients/#{patient.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Consultas")
    expect(response.body).to include("Agendar")
    expect(response.body).to include("Especialidade")
    expect(response.body).to include("Médico (opcional)")
    expect(response.body).to include("Dor de cabeça")
    expect(response.body).to include(consultation_path(consultation))
  end

  it "schedules a consultation from the patient page with an optional doctor" do
    patient = create_patient(user: user, organization: organization)
    doctor = create_doctor(organization: organization)
    specialty = create_specialty
    assign_specialty(doctor: doctor, specialty: specialty)

    expect {
      post "/consultations", params: {
        patient_id: patient.id,
        consultation: {
          patient_id: patient.id,
          specialty_id: specialty.id,
          scheduled_at: 2.days.from_now,
          user_id: doctor.id
        }
      }
    }.to change { patient.consultations.count }.by(1)

    expect(response).to have_http_status(:found)
    expect(patient.consultations.last.user).to eq(doctor)
    expect(patient.consultations.last.specialty).to eq(specialty)
  end

  it "schedules a consultation with only the specialty when no doctor is chosen" do
    patient = create_patient(user: user, organization: organization)
    specialty = create_specialty
    doctor = create_doctor(organization: organization)
    assign_specialty(doctor: doctor, specialty: specialty)

    post "/consultations", params: {
      patient_id: patient.id,
      consultation: { patient_id: patient.id, specialty_id: specialty.id, scheduled_at: 2.days.from_now }
    }

    expect(response).to have_http_status(:found)
    expect(patient.consultations.last.user).to be_nil
    expect(patient.consultations.last.specialty).to eq(specialty)
  end

  it "does not schedule a consultation for inactive patients" do
    patient = create_patient(user: user, organization: organization, active: false)
    specialty = create_specialty
    doctor = create_doctor(organization: organization)
    assign_specialty(doctor: doctor, specialty: specialty)

    post "/consultations", params: {
      patient_id: patient.id,
      consultation: { patient_id: patient.id, specialty_id: specialty.id, scheduled_at: 2.days.from_now }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(patient.consultations.reload).to be_empty
  end

  it "only lists specialties from active doctors in the current organization" do
    patient = create_patient(user: user, organization: organization)
    current_specialty = create_specialty(name: "Cardiologia")
    other_specialty = create_specialty(name: "Dermatologia")
    inactive_specialty = create_specialty(name: "Neurologia")
    doctor = create_doctor(organization: organization)
    assign_specialty(doctor: doctor, specialty: current_specialty)

    other_org = create_organization
    other_doctor = create_doctor(organization: other_org)
    assign_specialty(doctor: other_doctor, specialty: other_specialty)

    inactive_doctor = create_doctor(organization: organization)
    inactive_doctor.doctor_profile.update!(active: false)
    assign_specialty(doctor: inactive_doctor, specialty: inactive_specialty)

    get "/patients/#{patient.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Cardiologia")
    expect(response.body).not_to include("Dermatologia")
    expect(response.body).not_to include("Neurologia")
  end

  it "rejects specialties that are not linked to a doctor in the current organization" do
    patient = create_patient(user: user, organization: organization)
    unlinked_specialty = create_specialty(name: "Ortopedia")

    post "/consultations", params: {
      patient_id: patient.id,
      consultation: { patient_id: patient.id, specialty_id: unlinked_specialty.id, scheduled_at: 2.days.from_now }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(patient.consultations.reload).to be_empty
  end

  it "forces doctors to schedule consultations for themselves" do
    doctor = create_doctor(organization: organization)
    other_doctor = create_doctor(organization: organization)
    patient = create_patient(user: user, organization: organization)
    specialty = create_specialty
    assign_specialty(doctor: doctor, specialty: specialty)
    assign_specialty(doctor: other_doctor, specialty: specialty)
    Consultation.create!(
      patient: patient,
      user: doctor,
      organization: organization,
      specialty: specialty,
      scheduled_at: 1.day.ago,
      finished_at: Time.current,
      status: "completed"
    )
    sign_in_web(doctor)

    expect {
      post "/consultations", params: {
        patient_id: patient.id,
        consultation: {
          patient_id: patient.id,
          specialty_id: specialty.id,
          scheduled_at: 2.days.from_now,
          user_id: other_doctor.id
        }
      }
    }.to change { patient.consultations.count }.by(1)

    expect(response).to have_http_status(:found)
    expect(patient.consultations.last.user).to eq(doctor)
  end

  it "does not show specialist selection to doctors" do
    doctor = create_doctor(organization: organization)
    patient = create_patient(user: user, organization: organization)
    specialty = create_specialty
    assign_specialty(doctor: doctor, specialty: specialty)
    Consultation.create!(
      patient: patient,
      user: doctor,
      organization: organization,
      specialty: specialty,
      scheduled_at: 1.day.ago,
      finished_at: Time.current,
      status: "completed"
    )
    sign_in_web(doctor)

    get "/patients/#{patient.id}"

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Especialidade")
    expect(response.body).not_to include("Médico (opcional)")
  end

  it "requires specialty when scheduling from the patient page" do
    patient = create_patient(user: user, organization: organization)

    post "/consultations", params: {
      patient_id: patient.id,
      consultation: { patient_id: patient.id, scheduled_at: 2.days.from_now }
    }

    expect(response).to have_http_status(:unprocessable_entity)
    expect(patient.consultations.reload).to be_empty
  end

  it "does not expose patients from another organization (404)" do
    other_org = create_organization
    other_user = create_org_responsible(organization: other_org)
    foreign = create_patient(user: other_user, organization: other_org)

    get "/patients/#{foreign.id}"
    expect(response).to have_http_status(:not_found)
  end
end
