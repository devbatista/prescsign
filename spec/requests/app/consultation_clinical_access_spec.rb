require "rails_helper"

# Sigilo do conteúdo clínico da consulta (decisão de 16/10/2026; LGPD, art. 11):
# queixa é da agenda da organização; diagnóstico e notas, só do médico da
# consulta. Ver ConsultationPolicy#chief_complaint? e #clinical_notes?.
RSpec.describe "App::Consultations (sigilo do conteúdo clínico)", type: :request do
  let(:organization) { create_organization }
  let(:specialty) { create_specialty }
  let(:author) { create_doctor(organization: organization).tap { |doctor| assign_specialty(doctor: doctor, specialty: specialty) } }
  let(:other_doctor) { create_doctor(organization: organization) }
  let(:reception) { create_org_responsible(organization: organization) }
  let(:patient) { create_patient(user: reception, organization: organization) }
  let!(:consultation) do
    Consultation.create!(
      patient: patient, user: author, organization: organization, specialty: specialty,
      scheduled_at: 1.day.ago, finished_at: Time.current, status: "completed",
      chief_complaint: "Dor torácica ao esforço",
      diagnosis: "Angina instável",
      notes: "Histórico familiar de infarto"
    )
  end

  before { use_app_host! }

  # Com vínculo na organização: é o vínculo que dá acesso ao painel. Sem ele, o
  # usuário nem chega à consulta (coberto abaixo).
  def platform_user(role)
    create_user(organization: organization).tap do |user|
      create_membership(user: user, organization: organization, role: "staff")
      grant_role(user, role)
    end
  end

  def show_as(user)
    sign_in_web(user)
    get "/consultations/#{consultation.id}"
    response.body
  end

  it "o médico da consulta vê queixa, diagnóstico e notas" do
    body = show_as(author)

    expect(body).to include("Dor torácica ao esforço", "Angina instável", "Histórico familiar de infarto")
  end

  it "outro médico da organização vê a queixa, mas não o diagnóstico nem as notas" do
    body = show_as(other_doctor)

    expect(body).to include("Dor torácica ao esforço")
    expect(body).not_to include("Angina instável")
    expect(body).not_to include("Histórico familiar de infarto")
    expect(body).to include("visíveis apenas para o médico da consulta")
  end

  it "a recepção vê a queixa, mas não o diagnóstico nem as notas" do
    body = show_as(reception)

    expect(body).to include("Dor torácica ao esforço")
    expect(body).not_to include("Angina instável")
    expect(body).not_to include("Histórico familiar de infarto")
  end

  %w[admin support].each do |role|
    it "#{role} da plataforma não vê conteúdo clínico nenhum" do
      user = platform_user(role)
      body = show_as(user)

      expect(response).to have_http_status(:ok)
      expect(body).not_to include("Dor torácica ao esforço")
      expect(body).not_to include("Angina instável")
      expect(body).not_to include("Histórico familiar de infarto")

      get "/consultations"
      expect(response.body).not_to include("Dor torácica ao esforço")
    end
  end

  it "papel da plataforma sem vínculo na organização nem chega à consulta" do
    user = create_user(organization: organization).tap { |u| grant_role(u, "support") }
    sign_in_web(user)

    get "/consultations/#{consultation.id}"

    expect(response).to have_http_status(:found)
    expect(response.body).not_to include("Dor torácica ao esforço")
  end

  describe "escrita" do
    it "o médico da consulta registra diagnóstico e notas" do
      sign_in_web(author)

      patch "/consultations/#{consultation.id}", params: { consultation: { diagnosis: "Angina estável", notes: "Revisado" } }

      expect(consultation.reload.diagnosis).to eq("Angina estável")
      expect(consultation.notes).to eq("Revisado")
    end

    it "a recepção não oferece nem grava diagnóstico e notas, mas atualiza a queixa" do
      sign_in_web(reception)

      get "/consultations/#{consultation.id}/edit"
      form = Nokogiri::HTML(response.body)
      expect(form.at_css("textarea[name='consultation[chief_complaint]']")).to be_present
      expect(form.at_css("textarea[name='consultation[diagnosis]']")).to be_nil
      expect(form.at_css("textarea[name='consultation[notes]']")).to be_nil

      # Requisição montada à mão, com os campos que o formulário não oferece.
      patch "/consultations/#{consultation.id}", params: { consultation: {
        chief_complaint: "Retorno", diagnosis: "Adulterado", notes: "Adulterado"
      } }

      consultation.reload
      expect(consultation.chief_complaint).to eq("Retorno")
      expect(consultation.diagnosis).to eq("Angina instável")
      expect(consultation.notes).to eq("Histórico familiar de infarto")
    end

    it "outro médico da organização não grava diagnóstico na consulta de um colega" do
      sign_in_web(other_doctor)

      patch "/consultations/#{consultation.id}", params: { consultation: { diagnosis: "Adulterado" } }

      expect(consultation.reload.diagnosis).to eq("Angina instável")
    end

    it "a recepção agenda com o motivo, e notas enviadas por ela são ignoradas" do
      sign_in_web(reception)

      post "/consultations", params: { consultation: {
        patient_id: patient.id, specialty_id: specialty.id, user_id: author.id,
        scheduled_at: 1.day.from_now.iso8601, status: "scheduled",
        chief_complaint: "Primeira consulta", notes: "Escrito pela recepção"
      } }

      created = Consultation.order(:created_at).last
      expect(created.chief_complaint).to eq("Primeira consulta")
      expect(created.notes).to be_nil
    end

    it "o médico que agenda para si já pode registrar notas no agendamento" do
      sign_in_web(author)

      get "/consultations/new", params: { patient_id: patient.id }

      expect(Nokogiri::HTML(response.body).at_css("textarea[name='consultation[notes]']")).to be_present
    end
  end
end
