require "rails_helper"

RSpec.describe "App::Documents (prescriptions, certificates, signing)", type: :request do
  let(:organization) { create_organization }
  let(:doctor) { create_doctor(organization: organization) }
  let(:patient) { create_patient(user: doctor, organization: organization) }

  describe "prescription issuance and signing (as doctor)" do
    before do
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

    it "signs a document" do
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
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
  end
end
