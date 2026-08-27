require "rails_helper"

RSpec.describe "App::Medications (busca no catálogo)", type: :request do
  let(:organization) { create_organization }
  let(:doctor) { create_doctor(organization: organization) }

  before do
    sign_in_web(doctor)
    use_app_host!
  end

  def results
    JSON.parse(response.body).fetch("results")
  end

  it "busca por nome e devolve o que distingue a apresentação" do
    create_medication(
      name: "DORLESS", strength: "50 MG", active_ingredient: "CLORIDRATO DE TRAMADOL",
      presentation: "50 MG CAP DURA CT BL X 20", manufacturer: "LAB ALFA",
      control_class: "tarja_vermelha_retencao", default_posology: "1 cápsula de 8/8h"
    )

    get "/medications/search", params: { q: "dorl" }

    expect(response).to have_http_status(:ok)
    expect(results.first).to include(
      "name" => "DORLESS",
      "label" => "DORLESS 50 MG",
      "strength" => "50 MG",
      "active_ingredient" => "CLORIDRATO DE TRAMADOL",
      "presentation" => "50 MG CAP DURA CT BL X 20",
      "manufacturer" => "LAB ALFA",
      "posology" => "1 cápsula de 8/8h",
      "control_class" => "tarja_vermelha_retencao"
    )
  end

  it "busca também por princípio ativo e por EAN" do
    create_medication(name: "AMOXIBETA", active_ingredient: "AMOXICILINA", ean: "7891000000028")

    get "/medications/search", params: { q: "amoxicilina" }
    expect(results.map { |row| row["name"] }).to eq([ "AMOXIBETA" ])

    get "/medications/search", params: { q: "7891000000028" }
    expect(results.map { |row| row["name"] }).to eq([ "AMOXIBETA" ])
  end

  it "devolve o tipo SNCR derivado das substâncias do produto" do
    medication = create_medication(name: "RIVOGAMA", strength: "2 MG")
    medication.substances << Substance.create!(name: "clonazepam", list_344: "B1", sncr_type: "NRB")

    get "/medications/search", params: { q: "rivogama" }

    expect(results.first["sncr_type"]).to eq("NRB")
  end

  it "prioriza quem começa com o termo digitado" do
    create_medication(name: "CLORIDRATO DE SERTRALINA")
    create_medication(name: "SERTRALINA")

    get "/medications/search", params: { q: "sertralina" }

    expect(results.map { |row| row["name"] }).to eq([ "SERTRALINA", "CLORIDRATO DE SERTRALINA" ])
  end

  it "ignora medicamento desativado no back-office" do
    create_medication(name: "DESCONTINUADO", active: false)

    get "/medications/search", params: { q: "descontinuado" }

    expect(results).to be_empty
  end

  it "não busca com menos de dois caracteres" do
    create_medication(name: "DORLESS")

    get "/medications/search", params: { q: "d" }

    expect(results).to be_empty
  end

  it "limita o número de resultados" do
    (App::MedicationsController::RESULT_LIMIT + 5).times { |index| create_medication(name: "TESTINA #{index}") }

    get "/medications/search", params: { q: "testina" }

    expect(results.size).to eq(App::MedicationsController::RESULT_LIMIT)
  end

  it "exige autenticação" do
    sign_out doctor

    get "/medications/search", params: { q: "dorless" }

    expect(response).to have_http_status(:found)
  end
end
