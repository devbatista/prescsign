require "rails_helper"

# Busca da identificação assistida. A base é só a lista controlada, então "não
# encontrou" é uma resposta com significado — ver docs/CLASSIFICACAO_CONTROLADA.md.
RSpec.describe "App::Substances (busca assistida)", type: :request do
  let(:organization) { create_organization }
  let(:doctor) { create_doctor(organization: organization) }

  before do
    sign_in_web(doctor)
    use_app_host!
  end

  def results
    JSON.parse(response.body).fetch("results")
  end

  it "devolve a substância com a lista e o tipo que ela impõe" do
    Substance.create!(name: "clonazepam", list_344: "B1", sncr_type: "NRB")

    get "/substances/search", params: { q: "clona" }

    expect(response).to have_http_status(:ok)
    expect(results.size).to eq(1)
    expect(results.first).to include(
      "name" => "clonazepam", "list_344" => "B1", "sncr_type" => "NRB",
      "sncr_type_label" => Prescription::SNCR_TYPE_LABELS["NRB"]
    )
  end

  it "prioriza quem começa com o termo sobre quem só o contém" do
    Substance.create!(name: "metilfenidato", list_344: "A3", sncr_type: "NRA")
    Substance.create!(name: "fenidato composto", list_344: "C1", sncr_type: "RCE")

    get "/substances/search", params: { q: "fenidato" }

    expect(results.map { |r| r["name"] }.first).to eq("fenidato composto")
  end

  it "ignora substância inativa" do
    Substance.create!(name: "substancia arquivada", list_344: "C1", sncr_type: "RCE", active: false)

    get "/substances/search", params: { q: "arquivada" }

    expect(results).to be_empty
  end

  it "não busca com termo curto demais" do
    Substance.create!(name: "morfina", list_344: "A1", sncr_type: "NRA")

    get "/substances/search", params: { q: "m" }

    expect(results).to be_empty
  end

  it "exige autenticação" do
    sign_out doctor

    get "/substances/search", params: { q: "morfina" }

    expect(response).to have_http_status(:redirect)
  end
end
