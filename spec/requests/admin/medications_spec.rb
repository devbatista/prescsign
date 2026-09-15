require "rails_helper"

RSpec.describe "Admin::Medications (back-office)", type: :request do
  def create_support(organization:)
    user = create_user(organization: organization)
    grant_role(user, "support")
    user
  end

  describe "as a platform admin" do
    let(:admin) { create_admin(organization: create_organization) }

    before do
      sign_in_web(admin)
      use_admin_host!
    end

    it "lists the catalog" do
      create_medication(name: "Dipirona Sódica")

      get "/medications"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Medicamentos")
      expect(response.body).to include("Dipirona Sódica")
    end

    it "filters by search term" do
      create_medication(name: "Amoxicilina")
      create_medication(name: "Losartana")

      get "/medications", params: { q: "Amoxicilina" }

      expect(response.body).to include("Amoxicilina")
      expect(response.body).not_to include("Losartana")
    end

    it "filters by status" do
      create_medication(name: "Ativo SA", active: true)
      create_medication(name: "Inativo SA", active: false)

      get "/medications", params: { status: "inactive" }

      expect(response.body).to include("Inativo SA")
      expect(response.body).not_to include("Ativo SA")
    end

    it "renders the new form" do
      get "/medications/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Novo medicamento")
      expect(response.body).to include("Princípio ativo")
    end

    it "creates a medication" do
      expect {
        post "/medications", params: { medication: {
          name: "Dipirona", active_ingredient: "Dipirona monoidratada", strength: "500 mg",
          pharmaceutical_form: "comprimido", control_class: "comum", active: "1"
        } }
      }.to change(Medication, :count).by(1)

      medication = Medication.order(:created_at).last
      expect(response).to redirect_to("/medications/#{medication.id}")
      expect(medication.name).to eq("Dipirona")
    end

    it "re-renders the form on invalid input" do
      expect {
        post "/medications", params: { medication: { name: "" } }
      }.not_to change(Medication, :count)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "updates a medication" do
      medication = create_medication(name: "Antigo")

      patch "/medications/#{medication.id}", params: { medication: { name: "Novo Nome" } }

      expect(response).to redirect_to("/medications/#{medication.id}")
      expect(medication.reload.name).to eq("Novo Nome")
    end

    it "confirma que a tarja é ruído, registra quem confirmou e tira o produto da fila" do
      medication = create_medication(name: "Glicose 5%", control_class: "tarja_preta")
      expect(Medication.unclassified_controlled).to include(medication)

      patch "/medications/#{medication.id}", params: {
        medication: { uncontrolled_confirmed: "1", uncontrolled_confirmed_reason: "eletrólito; fora da 344/98" }
      }

      expect(response).to redirect_to("/medications/#{medication.id}")
      medication.reload
      expect(medication).to be_uncontrolled_confirmed
      expect(medication.uncontrolled_confirmed_by).to eq(admin)
      expect(Medication.unclassified_controlled).not_to include(medication)

      get "/medications/#{medication.id}"
      expect(response.body).to include("Confirmado não controlado")
      expect(response.body).to include("eletrólito; fora da 344/98")
      expect(response.body).to include(admin.email)
    end

    it "mostra na página do produto que a contradição está pendente e bloqueia a emissão" do
      medication = create_medication(name: "Glicose 5%", control_class: "tarja_preta")

      get "/medications/#{medication.id}"

      expect(response.body).to include("Pendente — bloqueia a emissão")
    end

    it "não troca o autor da confirmação ao editar outro campo depois" do
      other_admin = create_admin(organization: create_organization)
      medication = create_medication(
        name: "Glicose 5%", control_class: "tarja_preta",
        uncontrolled_confirmed: true, uncontrolled_confirmed_reason: "ruído", uncontrolled_confirmed_by: other_admin
      )

      patch "/medications/#{medication.id}", params: {
        medication: { default_posology: "Conforme prescrição", uncontrolled_confirmed: "1",
                      uncontrolled_confirmed_reason: "ruído" }
      }

      expect(medication.reload.uncontrolled_confirmed_by).to eq(other_admin)
    end

    it "recusa confirmar sem motivo" do
      medication = create_medication(name: "Glicose 5%", control_class: "tarja_preta")

      patch "/medications/#{medication.id}", params: { medication: { uncontrolled_confirmed: "1" } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(medication.reload).not_to be_uncontrolled_confirmed
    end

    it "deactivates and reactivates a medication" do
      medication = create_medication(name: "Toggle", active: true)

      patch "/medications/#{medication.id}/deactivate"
      expect(response).to redirect_to("/medications/#{medication.id}")
      expect(medication.reload.active).to be(false)

      patch "/medications/#{medication.id}/activate"
      expect(medication.reload.active).to be(true)
    end
  end

  describe "as platform support (read-only)" do
    let(:support) { create_support(organization: create_organization) }
    let(:medication) { create_medication(name: "Somente Leitura") }

    before do
      sign_in_web(support)
      use_admin_host!
    end

    it "can list and view the catalog" do
      get "/medications"
      expect(response).to have_http_status(:ok)

      get "/medications/#{medication.id}"
      expect(response).to have_http_status(:ok)
    end

    it "cannot create (write restricted to admin)" do
      expect {
        post "/medications", params: { medication: { name: "Bloqueado" } }
      }.not_to change(Medication, :count)

      expect(response).to have_http_status(:forbidden)
    end

    it "cannot deactivate (write restricted to admin)" do
      patch "/medications/#{medication.id}/deactivate"

      expect(response).to have_http_status(:forbidden)
      expect(medication.reload.active).to be(true)
    end
  end

  describe "as a non-platform user" do
    let(:responsible) { create_org_responsible(organization: create_organization) }

    before do
      sign_in_web(responsible)
      use_admin_host!
    end

    it "is redirected out of the back-office" do
      get "/medications"
      expect(response).to have_http_status(:found)
    end
  end
end
