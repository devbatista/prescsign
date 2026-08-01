require "rails_helper"

RSpec.describe "Admin::Substances (back-office)", type: :request do
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

    it "lists substances" do
      Substance.create!(name: "Clonazepam", sncr_type: "NRB")

      get "/substances"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Substâncias")
      expect(response.body).to include("Clonazepam")
    end

    it "filters by search term" do
      Substance.create!(name: "Clonazepam")
      Substance.create!(name: "Amoxicilina")

      get "/substances", params: { q: "Clonaz" }

      expect(response.body).to include("Clonazepam")
      expect(response.body).not_to include("Amoxicilina")
    end

    it "filters only controlled substances" do
      Substance.create!(name: "Morfina", sncr_type: "NRA")
      Substance.create!(name: "Dipirona sódica")

      get "/substances", params: { sncr_type: "controlled" }

      expect(response.body).to include("Morfina")
      expect(response.body).not_to include("Dipirona sódica")
    end

    it "renders the new form" do
      get "/substances/new"

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Nova substância")
      expect(response.body).to include("Tipo SNCR")
    end

    it "creates a substance" do
      expect {
        post "/substances", params: { substance: { name: "Clonazepam", list_344: "B1", sncr_type: "NRB", active: "1" } }
      }.to change(Substance, :count).by(1)

      substance = Substance.order(:created_at).last
      expect(response).to redirect_to("/substances/#{substance.id}")
      expect(substance.sncr_type).to eq("NRB")
    end

    it "re-renders the form on invalid input" do
      expect {
        post "/substances", params: { substance: { name: "" } }
      }.not_to change(Substance, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "updates a substance" do
      substance = Substance.create!(name: "Antiga")

      patch "/substances/#{substance.id}", params: { substance: { sncr_type: "RCE" } }

      expect(response).to redirect_to("/substances/#{substance.id}")
      expect(substance.reload.sncr_type).to eq("RCE")
    end

    it "toggles activation" do
      substance = Substance.create!(name: "Toggle", active: true)

      patch "/substances/#{substance.id}/deactivate"
      expect(substance.reload.active).to be(false)

      patch "/substances/#{substance.id}/activate"
      expect(substance.reload.active).to be(true)
    end
  end

  describe "as platform support (read-only)" do
    let(:support) { create_support(organization: create_organization) }
    let(:substance) { Substance.create!(name: "Somente Leitura") }

    before do
      sign_in_web(support)
      use_admin_host!
    end

    it "can list and view" do
      get "/substances"
      expect(response).to have_http_status(:ok)

      get "/substances/#{substance.id}"
      expect(response).to have_http_status(:ok)
    end

    it "cannot create (write restricted to admin)" do
      expect {
        post "/substances", params: { substance: { name: "Bloqueada" } }
      }.not_to change(Substance, :count)

      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "linking substances to a medication" do
    let(:admin) { create_admin(organization: create_organization) }

    before do
      sign_in_web(admin)
      use_admin_host!
    end

    it "assigns substances via the medication form and derives the effective type" do
      substance = Substance.create!(name: "Clonazepam", sncr_type: "NRB")
      medication = create_medication(name: "Rivotril")

      patch "/medications/#{medication.id}", params: { medication: { substance_ids: [ substance.id ] } }

      expect(medication.reload.substances).to include(substance)
      expect(medication.effective_sncr_type).to eq("NRB")
    end
  end
end
