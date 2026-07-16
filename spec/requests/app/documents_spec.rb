require "rails_helper"

RSpec.describe "App::Documents (prescriptions, certificates, signing)", type: :request do
  let(:organization) { create_organization }
  let(:doctor) { create_doctor(organization: organization) }
  let(:patient) { create_patient(user: doctor, organization: organization) }

  describe "prescription issuance and signing (as doctor)" do
    before do
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
      use_app_host!
    end

    it "creates a prescription with its document" do
      expect {
        post "/prescriptions", params: { prescription: {
          patient_id: patient.id, issued_on: Date.current.iso8601, content: "Amoxicilina 500mg"
        } }
      }.to change(Prescription, :count).by(1).and change(Document, :count).by(1)
      expect(response).to have_http_status(:found)
      expect(response.location).to match(%r{/documents/})
    end

    it "shows the document hub" do
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
      get "/documents/#{prescription.document.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ações")
    end

    it "lists available documents grouped by kind from the documents menu" do
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
      linked_patient = create_patient(user: create_org_responsible(organization: organization), organization: organization)
      unlinked_patient = create_patient(user: create_org_responsible(organization: organization), organization: organization)
      specialty = doctor.doctor_profile.specialties.first
      Consultation.create!(
        patient: linked_patient,
        user: doctor,
        organization: organization,
        specialty: specialty,
        scheduled_at: 1.day.ago,
        finished_at: Time.current,
        status: "completed"
      )
      certificate = create_medical_certificate_document(user: doctor, patient: linked_patient, organization: organization)
      hidden_prescription = create_prescription_document(
        user: create_org_responsible(organization: organization),
        patient: unlinked_patient,
        organization: organization
      )

      get "/documents"

      expect(response).to have_http_status(:ok)
      expect(nav_link_for("/documents")).to be_present
      expect(nav_link_for("/documents")["class"]).to include("bg-ps-info-bg")
      expect(nav_link_for("/documents").text).to eq("Documentos")
      expect(nav_link_for("/prescriptions/new")).to be_nil
      expect(nav_link_for("/medical_certificates/new")).to be_nil
      expect(response.body).to include("Receitas emitidas")
      expect(response.body).to include("Atestados emitidos")
      expect(response.body).to include("Nova receita")
      expect(response.body).to include("Novo atestado")
      expect(response.body).to include(prescription.document.code)
      expect(response.body).to include(certificate.document.code)
      expect(response.body).not_to include(hidden_prescription.document.code)
    end

    it "paginates document cards independently" do
      oldest_prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
      10.times { create_prescription_document(user: doctor, patient: patient, organization: organization) }

      get "/documents"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Página 1 de 2 · 11 no total")
      expect(response.body).not_to include(oldest_prescription.document.code)
      expect(response.body).to include("prescriptions_page=2")

      get "/documents", params: { prescriptions_page: 2 }

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Página 2 de 2 · 11 no total")
      expect(response.body).to include(oldest_prescription.document.code)
    end

    it "signs a document" do
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
      patch "/documents/#{prescription.document.id}/sign"
      expect(response).to have_http_status(:found)
      expect(prescription.document.reload.status).to eq("sent")
      expect(prescription.reload.status).to eq("signed")
    end

    it "allows doctors to manage documents for patients linked to their consultations" do
      responsible = create_org_responsible(organization: organization)
      linked_patient = create_patient(user: responsible, organization: organization)
      specialty = doctor.doctor_profile.specialties.first
      Consultation.create!(
        patient: linked_patient,
        user: doctor,
        organization: organization,
        specialty: specialty,
        scheduled_at: 1.day.ago,
        finished_at: Time.current,
        status: "completed"
      )
      prescription = create_prescription_document(user: responsible, patient: linked_patient, organization: organization)

      get "/documents/#{prescription.document.id}"
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Ações")
      expect(response.body).to include("Assinar documento")

      patch "/documents/#{prescription.document.id}/sign"
      expect(response).to have_http_status(:found)
      expect(prescription.document.reload.status).to eq("sent")
      expect(prescription.reload.status).to eq("signed")
    end

    it "revokes a prescription" do
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
      patch "/prescriptions/#{prescription.id}/revoke"
      expect(response).to have_http_status(:found)
      expect(prescription.document.reload.status).to eq("revoked")
      expect(prescription.reload.status).to eq("cancelled")
    end
  end

  describe "medical certificate issuance (as doctor)" do
    before do
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
      use_app_host!
    end

    it "creates a certificate calculating the end date from rest days" do
      start_on = Date.current

      expect {
        post "/medical_certificates", params: { medical_certificate: {
          patient_id: patient.id,
          issued_on: Date.current.iso8601,
          rest_start_on: start_on.iso8601,
          rest_days: 3,
          content: "Afastamento por sintomas gripais"
        } }
      }.to change(MedicalCertificate, :count).by(1).and change(Document, :count).by(1)

      certificate = MedicalCertificate.order(:created_at).last
      expect(response).to have_http_status(:found)
      expect(response.location).to match(%r{/documents/})
      expect(certificate.rest_end_on).to eq(start_on + 2.days)
    end
  end

  describe "authorization" do
    it "forbids a non-doctor from signing" do
      responsible = create_org_responsible(organization: organization)
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)

      sign_in_web(responsible)
      use_app_host!
      patch "/documents/#{prescription.document.id}/sign"
      expect(response).to have_http_status(:forbidden)
      expect(prescription.document.reload.status).to eq("issued")
    end

    it "does not show the documents menu for a doctor with admin persona" do
      admin_doctor = create_admin(organization: organization)
      grant_role(admin_doctor, "doctor")
      create_doctor_profile(user: admin_doctor)

      sign_in_web(admin_doctor)
      use_app_host!

      get "/documents"

      expect(response).to have_http_status(:ok)
      expect(nav_link_for("/documents")).to be_nil
    end
  end

  def create_medical_certificate_document(user:, patient:, organization:)
    certificate = user.medical_certificates.create!(
      patient: patient,
      organization: organization,
      code: SecureRandom.alphanumeric(10).upcase,
      status: "draft",
      content: "Afastamento por teste",
      issued_on: Date.current,
      rest_start_on: Date.current,
      rest_days: 2
    )
    Documents::LifecycleService.new(actor: user).create_with_initial_version!(
      user: user,
      patient: patient,
      documentable: certificate,
      unit: organization.default_unit,
      kind: "medical_certificate",
      issued_on: certificate.issued_on,
      content: certificate.content
    )
    certificate.reload
  end
end
