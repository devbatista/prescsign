require "rails_helper"

# Fecha a falha silenciosa: antes, medicamento controlado digitado à mão (em vez
# de escolhido no catálogo) não tinha de onde derivar o tipo e a receita saía
# comum, sem numeração SNCR e sem aviso. Ver docs/CLASSIFICACAO_CONTROLADA.md.
RSpec.describe "App::Prescriptions (classificação de item de texto livre)", type: :request do
  let(:organization) { create_organization }
  let(:doctor) { create_doctor(organization: organization) }
  let(:patient) { create_patient(user: doctor, organization: organization) }

  before do
    # PatientPolicy::Scope só entrega ao médico os pacientes com quem ele teve
    # consulta — sem isso o create devolve 404 antes de chegar na validação.
    specialty = create_specialty
    assign_specialty(doctor: doctor, specialty: specialty)
    Consultation.create!(
      patient: patient, user: doctor, organization: organization, specialty: specialty,
      scheduled_at: 1.day.ago, finished_at: Time.current, status: "completed"
    )
    sign_in_web(doctor)
    use_app_host!
  end

  def emit(items)
    post "/prescriptions", params: { prescription: {
      patient_id: patient.id, issued_on: Date.current.iso8601, content: "",
      prescription_items_attributes: items
    } }
  end

  def last_prescription
    Prescription.order(:created_at).last
  end

  describe "casamento automático sobre o texto livre" do
    it "classifica antibiótico digitado à mão como receita de retenção" do
      # O caso de maior volume: antimicrobiano da IN 360/2025 exige RET, e é o
      # que um clínico digita sem pensar duas vezes.
      Substance.create!(name: "amoxicilina", list_344: "IN 360/2025 art. 1º (antimicrobiano)", sncr_type: "RET")

      expect {
        emit("0" => { name: "Amoxicilina", strength: "500 mg", quantity: "1 caixa" })
      }.to change(Prescription, :count).by(1)

      prescription = last_prescription
      expect(prescription.sncr_type).to eq("RET")
      expect(prescription).to be_controlled
      expect(prescription.prescription_items.first.substance.name).to eq("amoxicilina")
    end

    it "desfaz o sal do texto digitado antes de casar" do
      Substance.create!(name: "tramadol", list_344: "C1", sncr_type: "RCE")

      emit("0" => { name: "Cloridrato de tramadol", strength: "50 mg" })

      expect(last_prescription.sncr_type).to eq("RCE")
    end

    it "casa também pelo princípio ativo quando o nome não entrega" do
      Substance.create!(name: "clonazepam", list_344: "B1", sncr_type: "NRB")

      emit("0" => { name: "Remédio da noite", active_ingredient: "clonazepam" })

      expect(last_prescription.sncr_type).to eq("NRB")
    end
  end

  describe "quando o sistema não consegue classificar" do
    it "não emite a receita" do
      expect {
        emit("0" => { name: "Fórmula manipulada da clínica", quantity: "1 frasco" })
      }.not_to change(Prescription, :count)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Não foi possível classificar")
    end

    it "manda selecionar do catálogo quando o nome digitado existe lá" do
      # Nome comercial que o matcher não alcança, mas que está no catálogo: o
      # médico digitou em vez de clicar na sugestão.
      create_medication(name: "Rivotril", strength: "2 mg")

      emit("0" => { name: "Rivotril", strength: "2 mg" })

      expect(response.body).to include("existe no catálogo")
      expect(Prescription.count).to eq(0)
    end

    it "emite como comum depois de o médico confirmar que nenhuma controlada se aplica" do
      expect {
        emit("0" => { name: "Fórmula manipulada da clínica", uncontrolled_confirmed: "1" })
      }.to change(Prescription, :count).by(1)

      prescription = last_prescription
      expect(prescription.sncr_type).to be_nil
      expect(prescription.prescription_items.first.uncontrolled_confirmed_at).to be_present
    end
  end

  describe "identificação assistida pelo médico" do
    it "deriva o tipo da substância identificada, e não de escolha do médico" do
      substance = Substance.create!(name: "hidroclorotiazida manipulada", list_344: "C1", sncr_type: "RCE")

      emit("0" => { name: "Fórmula manipulada 3-em-1", substance_id: substance.id })

      prescription = last_prescription
      expect(prescription.sncr_type).to eq("RCE")
      expect(prescription.prescription_items.first.substance_id).to eq(substance.id)
    end

    it "não deixa a confirmação de 'não controlado' apagar um casamento automático" do
      # A substância é a fonte de verdade: se o sistema reconhece, o médico não
      # pode declarar que não é controlada.
      Substance.create!(name: "clonazepam", list_344: "B1", sncr_type: "NRB")

      emit("0" => { name: "Clonazepam", strength: "2 mg", uncontrolled_confirmed: "1" })

      prescription = last_prescription
      expect(prescription.sncr_type).to eq("NRB")
      expect(prescription.prescription_items.first.uncontrolled_confirmed_at).to be_nil
    end
  end

  describe "quando o medicamento do item muda" do
    def confirmed_item_prescription
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
      item = prescription.prescription_items.create!(
        name: "Fórmula manipulada", uncontrolled_confirmed_at: Time.current
      )
      [ prescription, item ]
    end

    def rename_item(prescription, item, name)
      patch "/prescriptions/#{prescription.id}", params: { prescription: {
        issued_on: prescription.issued_on.iso8601, content: "",
        prescription_items_attributes: { "0" => { id: item.id, name: name } }
      } }
    end

    it "refaz a pergunta em vez de herdar a resposta dada sobre o texto anterior" do
      prescription, item = confirmed_item_prescription

      rename_item(prescription, item, "Outra fórmula")

      # Nada é persistido porque a receita não passa na validação — o médico
      # precisa responder de novo sobre o que passou a estar prescrito.
      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Não foi possível classificar")
      expect(item.reload.name).to eq("Fórmula manipulada")
    end

    it "reclassifica quando o novo texto casa com uma controlada" do
      Substance.create!(name: "morfina", list_344: "A1", sncr_type: "NRA")
      prescription, item = confirmed_item_prescription

      rename_item(prescription, item, "Morfina")

      expect(response).to have_http_status(:redirect)
      expect(item.reload.uncontrolled_confirmed_at).to be_nil
      expect(item.substance.name).to eq("morfina")
      expect(prescription.reload.sncr_type).to eq("NRA")
    end
  end

  describe "formulário" do
    it "oferece a busca assistida no item que ficou sem classificação" do
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
      prescription.prescription_items.create!(name: "Fórmula manipulada")

      get "/prescriptions/#{prescription.id}/edit"

      expect(response.body).to include("data-substance-search-url=\"/substances/search\"")
      expect(response.body).to include("Não identificamos")
    end

    it "não pergunta nada quando o item veio do catálogo" do
      medication = create_medication(name: "Dipirona", strength: "500 mg")
      prescription = create_prescription_document(user: doctor, patient: patient, organization: organization)
      prescription.prescription_items.create!(name: "Dipirona", medication: medication)

      get "/prescriptions/#{prescription.id}/edit"

      expect(response.body).not_to include("Não identificamos")
    end
  end
end
