require "rails_helper"

RSpec.describe "App::MedicalCertificates", type: :request do
  let(:organization) { create_organization }
  let(:doctor) { create_doctor(organization: organization) }
  let(:patient) { create_patient(user: doctor, organization: organization) }

  before do
    # PatientPolicy::Scope só entrega ao médico os pacientes com quem ele teve
    # consulta.
    specialty = create_specialty
    assign_specialty(doctor: doctor, specialty: specialty)
    Consultation.create!(
      patient: patient, user: doctor, organization: organization, specialty: specialty,
      scheduled_at: 1.day.ago, finished_at: Time.current, status: "completed"
    )
    sign_in_web(doctor)
    use_app_host!
  end

  def issue(overrides = {})
    post "/medical_certificates", params: { medical_certificate: {
      patient_id: patient.id, issued_on: Date.current.iso8601,
      rest_start_on: Date.current.iso8601, rest_days: 3,
      content: "Afastamento por sintomas gripais"
    }.merge(overrides) }
    MedicalCertificate.order(:created_at).last
  end

  def sign(certificate)
    patch "/documents/#{certificate.document.id}/sign"
    certificate.reload
  end

  describe "emissão" do
    it "abre o formulário com emissão e início do afastamento em hoje" do
      get "/medical_certificates/new", params: { patient_id: patient.id }

      expect(response).to have_http_status(:ok)
      form = Nokogiri::HTML(response.body)
      expect(form.at_css("input[name='medical_certificate[issued_on]']")["value"]).to eq(Date.current.iso8601)
      expect(form.at_css("input[name='medical_certificate[rest_start_on]']")["value"]).to eq(Date.current.iso8601)
    end

    it "emite o atestado com o documento, a versão inicial e o fim do afastamento calculado" do
      certificate = nil
      expect { certificate = issue(icd_code: " j11 ") }
        .to change(MedicalCertificate, :count).by(1)
        .and change(Document, :count).by(1)
        .and change(DocumentVersion, :count).by(1)

      expect(response).to redirect_to(document_path(certificate.document))
      expect(certificate.status).to eq("draft")
      expect(certificate.user).to eq(doctor)
      expect(certificate.rest_end_on).to eq(Date.current + 2.days)
      expect(certificate.icd_code).to eq("J11")
      expect(certificate.document.kind).to eq("medical_certificate")
      expect(certificate.document.current_version).to eq(1)
    end

    it "não emite sem o conteúdo e explica o motivo" do
      expect { issue(content: "") }.not_to change(MedicalCertificate, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(Document.count).to eq(0)
    end

    it "não emite com dias de afastamento inválidos" do
      expect { issue(rest_days: 0) }.not_to change(MedicalCertificate, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "não emite para paciente de outra organização" do
      other_organization = create_organization
      outsider = create_patient(user: create_org_responsible(organization: other_organization),
                                organization: other_organization)

      expect { issue(patient_id: outsider.id) }.not_to change(MedicalCertificate, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "edição" do
    it "atualiza o rascunho e gera uma nova versão do documento" do
      certificate = issue

      patch "/medical_certificates/#{certificate.id}", params: { medical_certificate: {
        content: "Afastamento revisado", rest_days: 5
      } }

      expect(response).to redirect_to(document_path(certificate.document))
      certificate.reload
      expect(certificate.content).to eq("Afastamento revisado")
      expect(certificate.rest_end_on).to eq(certificate.rest_start_on + 4.days)
      expect(certificate.document.reload.current_version).to eq(2)
      expect(AuditLog.where(resource: certificate, action: "updated")).to exist
    end

    it "mantém o rascunho quando a edição é inválida" do
      certificate = issue

      patch "/medical_certificates/#{certificate.id}", params: { medical_certificate: { content: "" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(certificate.reload.content).to eq("Afastamento por sintomas gripais")
      expect(certificate.document.reload.current_version).to eq(1)
    end

    it "não edita atestado assinado" do
      certificate = sign(issue)
      expect(certificate.status).to eq("signed")

      # Barrado pela policy (MedicalCertificatePolicy#update? exige rascunho),
      # antes do aviso amigável do controller.
      get "/medical_certificates/#{certificate.id}/edit"
      expect(response).to have_http_status(:forbidden)

      patch "/medical_certificates/#{certificate.id}", params: { medical_certificate: { content: "Adulterado" } }
      expect(response).to have_http_status(:forbidden)
      expect(certificate.reload.content).to eq("Afastamento por sintomas gripais")
    end
  end

  describe "revogação" do
    it "exige o motivo" do
      certificate = sign(issue)

      patch "/medical_certificates/#{certificate.id}/revoke", params: { reason: " " }

      expect(response).to redirect_to(document_path(certificate.document))
      expect(flash[:alert]).to eq("Informe o motivo da revogação.")
      expect(certificate.document.reload.status).not_to eq("revoked")
    end

    it "revoga com o motivo e registra na auditoria" do
      certificate = sign(issue)

      patch "/medical_certificates/#{certificate.id}/revoke", params: { reason: "Emitido para o paciente errado" }

      expect(response).to redirect_to(document_path(certificate.document))
      expect(certificate.document.reload.status).to eq("revoked")
      expect(AuditLog.where(document: certificate.document, action: "revoked")).to exist
    end
  end

  describe "PDF" do
    it "gera o PDF do rascunho na hora" do
      certificate = issue

      get "/medical_certificates/#{certificate.id}/pdf"

      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq("application/pdf")
      expect(response.headers["Content-Disposition"]).to include("atestado-#{certificate.code}-v1.pdf")
    end

    it "serve o PDF assinado guardado, sem gerar de novo" do
      certificate = sign(issue)
      stored = certificate.document.document_versions.find_by!(version_number: certificate.document.current_version)
                          .pdf_file.download
      expect(Documents::PdfRenderer).not_to receive(:new)

      get "/medical_certificates/#{certificate.id}/pdf"

      expect(response.body).to eq(stored)
    end
  end

  describe "autorização" do
    it "não deixa o suporte da plataforma emitir atestado" do
      support = create_user(organization: organization).tap do |user|
        create_membership(user: user, organization: organization, role: "staff")
        grant_role(user, "support")
      end
      sign_in_web(support)

      expect { issue }.not_to change(MedicalCertificate, :count)
      # Barrado pela policy de emissão, não por não enxergar o paciente.
      expect(response).to have_http_status(:forbidden)
    end

    it "não mostra a médico de outra organização o atestado de um paciente que não é dele" do
      certificate = issue
      other_organization = create_organization
      sign_in_web(create_doctor(organization: other_organization))

      get "/medical_certificates/#{certificate.id}/pdf"

      expect(response).to have_http_status(:not_found)
    end
  end
end
