require "rails_helper"

RSpec.describe "Public web document validation", type: :request do
  let(:organization) { create_organization }
  let(:doctor) { create_doctor(organization: organization) }
  let(:patient) { create_patient(user: doctor, organization: organization) }

  it "renders the code search form (no auth)" do
    use_app_host!
    get "/validate"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Código do documento")
  end

  it "shows a valid document with a QR code (no auth)" do
    prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
    use_app_host!
    get "/validate/#{prescription.document.code}"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Documento válido")
    expect(response.body).to include("<svg")
  end

  it "handles an unknown code gracefully" do
    use_login_host!
    get "/validate/NOPE99999"
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("não encontrado")
  end
end
