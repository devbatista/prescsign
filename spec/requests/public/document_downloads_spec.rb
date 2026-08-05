require "rails_helper"

RSpec.describe "Public::DocumentDownloads", type: :request do
  let(:organization) { create_organization }
  let(:doctor) { create_doctor(organization: organization) }
  let(:patient) { create_patient(user: doctor, organization: organization) }

  def signed_document
    prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
    Documents::SigningService.new(actor: doctor).sign!(document: prescription.document)
    prescription.document.reload
  end

  it "serve o PDF assinado para um token válido" do
    document = signed_document

    get "/d", params: { token: document.patient_download_token }

    expect(response).to have_http_status(:ok)
    expect(response.media_type).to eq("application/pdf")
    expect(response.body).to be_present
  end

  it "responde 404 com página amigável para token inválido" do
    get "/d", params: { token: "token-invalido" }

    expect(response).to have_http_status(:not_found)
    expect(response.body).to include("Link indisponível")
  end

  it "responde 404 sem token" do
    get "/d"

    expect(response).to have_http_status(:not_found)
  end

  it "responde 404 para token expirado" do
    document = signed_document
    expired = document.signed_id(purpose: Document::PATIENT_DOWNLOAD_PURPOSE, expires_in: -1.second)

    get "/d", params: { token: expired }

    expect(response).to have_http_status(:not_found)
  end

  it "não aceita token gerado para outra finalidade (purpose)" do
    document = signed_document
    other_purpose = document.signed_id(purpose: :something_else, expires_in: 1.hour)

    get "/d", params: { token: other_purpose }

    expect(response).to have_http_status(:not_found)
  end
end
