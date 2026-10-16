require "rails_helper"

# A classificação de controle é derivada no save da receita, mas a assinatura
# não salva: recarrega o rascunho e assina com o tipo gravado na emissão. Se a
# base de controladas mudar entre a emissão e a assinatura, o rascunho não pode
# sair como receita comum. Ver Prescription#control_classification_stale?.
RSpec.describe "App::Documents (classificação muda entre emissão e assinatura)", type: :request do
  let(:organization) { create_organization }
  let(:doctor) { create_doctor(organization: organization) }
  let(:patient) { create_patient(user: doctor, organization: organization) }

  before do
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
    Prescription.order(:created_at).last
  end

  def sign(prescription)
    patch "/documents/#{prescription.document.id}/sign"
  end

  def give_pool(sncr_type)
    SncrNumbering.import_numbers!(doctor_profile: doctor.doctor_profile, sncr_type: sncr_type, numbers: [ "2411.1-00.0000001" ])
  end

  def expect_blocked_for_review(prescription)
    expect(response).to redirect_to(edit_prescription_path(prescription))
    expect(flash[:alert]).to include("classificação de controle dos medicamentos mudou")
    expect(prescription.reload.status).to eq("draft")
    expect(prescription.document.reload.status).to eq("issued")
  end

  describe "rascunho que hoje seria controlado" do
    it "bloqueia o produto que a curadoria vinculou a uma controlada depois da emissão" do
      medication = Medication.create!(name: "Produto sem vínculo", active: true)
      prescription = emit("0" => { name: medication.name, medication_id: medication.id })
      expect(prescription).not_to be_controlled

      medication.substances << Substance.create!(name: "clonazepam", list_344: "B1", sncr_type: "NRB")
      give_pool("NRB")

      sign(prescription)

      expect_blocked_for_review(prescription)
      # O bloqueio vem antes do portão: nenhum número é gasto.
      expect(SncrNumbering.find_by(number: "2411.1-00.0000001").status).not_to eq("consumed")
    end

    it "bloqueia o texto livre que passou a casar com uma controlada depois da emissão" do
      prescription = emit("0" => { name: "Zolpidem", strength: "10 mg", uncontrolled_confirmed: "1" })
      expect(prescription).not_to be_controlled

      Substance.create!(name: "zolpidem", list_344: "B1", sncr_type: "NRB")

      sign(prescription)

      expect_blocked_for_review(prescription)
    end

    it "bloqueia o produto cuja tarja passou a contradizer a base depois da emissão" do
      medication = Medication.create!(name: "Produto da CMED", active: true)
      prescription = emit("0" => { name: medication.name, medication_id: medication.id })

      # Reimportação mensal da CMED publica o produto com tarja de controlado.
      medication.update!(control_class: "tarja_preta")

      sign(prescription)

      expect_blocked_for_review(prescription)
    end
  end

  it "assina no receituário certo depois que o médico revisa e salva" do
    medication = Medication.create!(name: "Produto sem vínculo", active: true)
    prescription = emit("0" => { name: medication.name, medication_id: medication.id })
    medication.substances << Substance.create!(name: "clonazepam", list_344: "B1", sncr_type: "NRB")
    give_pool("NRB")
    sign(prescription)

    patch "/prescriptions/#{prescription.id}", params: { prescription: { issued_on: Date.current.iso8601 } }
    expect(prescription.reload.sncr_type).to eq("NRB")

    sign(prescription)

    expect(prescription.reload.status).to eq("signed")
    numbering = SncrNumbering.find_by(number: "2411.1-00.0000001")
    expect(numbering.status).to eq("consumed")
    expect(numbering.prescription_id).to eq(prescription.id)
  end

  # O snapshot controlado vale: uma correção na base não rebaixa em silêncio
  # uma receita emitida como controlada.
  it "não rebaixa a receita emitida como controlada quando a substância sai do produto" do
    medication = Medication.create!(name: "Rivotril 2mg", active: true)
    medication.substances << Substance.create!(name: "clonazepam", list_344: "B1", sncr_type: "NRB")
    prescription = emit("0" => { name: medication.name, medication_id: medication.id })
    expect(prescription.sncr_type).to eq("NRB")

    medication.medication_substances.destroy_all
    give_pool("NRB")

    sign(prescription)

    expect(prescription.reload.status).to eq("signed")
    expect(SncrNumbering.find_by(number: "2411.1-00.0000001").status).to eq("consumed")
  end
end
