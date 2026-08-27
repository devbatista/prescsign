require "rails_helper"
require "csv"

RSpec.describe Medications::CmedCatalogImport do
  let(:path) { Rails.root.join("spec/fixtures/cmed_medicamentos.csv") }
  let(:review_path) { Rails.root.join("tmp/spec_medications_import_review.csv") }
  let(:io) { StringIO.new }

  before do
    Substance.create!(name: "tramadol", list_344: "C1", sncr_type: "RCE")
    Substance.create!(name: "amoxicilina", list_344: "IN 360/2025 art. 1º (antimicrobiano)", sncr_type: "RET")
    Substance.create!(name: "ciprofloxacina", list_344: "IN 360/2025 art. 1º (antimicrobiano)", sncr_type: "RET")
    Substance.create!(name: "sulfadiazina", list_344: "IN 360/2025 art. 1º (antimicrobiano)", sncr_type: "RET")
    Substance.create!(name: "levodopa", list_344: "C1", sncr_type: "RCE")
    Substance.create!(name: "clonazepam", list_344: "B1", sncr_type: "NRB")
    FileUtils.rm_f(review_path)
  end

  after { FileUtils.rm_f(review_path) }

  def import
    described_class.call(path: path, io: io, review_path: review_path)
  end

  it "importa as apresentações derivando concentração, forma e tarja" do
    import

    medication = Medication.find_by(anvisa_registration: "1234500010011")
    expect(medication).to have_attributes(
      name: "DORLESS",
      active_ingredient: "CLORIDRATO DE TRAMADOL",
      strength: "50 MG",
      pharmaceutical_form: "capsula",
      control_class: "tarja_vermelha_retencao",
      manufacturer: "LABORATÓRIO ALFA LTDA",
      ean: "7891000000011",
      active: true
    )
    expect(medication.presentation).to start_with("50 MG CAP DURA")

    expect(Medication.find_by(name: "RIVOGAMA")).to have_attributes(control_class: "tarja_preta", ean: nil)
    expect(Medication.find_by(name: "DORALFA").control_class).to eq("comum")
    # "- (*)" é ausência de informação na fonte: não vira "comum".
    expect(Medication.find_by(name: "QUEIMALFA")).to have_attributes(control_class: nil, active: false)
  end

  it "ignora a linha repetida e mantém o EAN só no produto em comercialização" do
    import

    expect(Medication.where(name: "DORALFA").count).to eq(1)

    marketed, discontinued = Medication.where(name: "RESPIBETA").order(:anvisa_registration).to_a.partition { |m| m.ean.present? }
    expect(marketed.map(&:anvisa_registration)).to eq([ "1234500080099" ])
    expect(discontinued.map(&:anvisa_registration)).to eq([ "1234500080081" ])
  end

  it "vincula as substâncias controladas desfazendo sal, hidratação e gênero" do
    import

    expect(Medication.find_by(name: "DORLESS").substances.map(&:name)).to eq([ "tramadol" ])
    expect(Medication.find_by(name: "AMOXIBETA").substances.map(&:name)).to eq([ "amoxicilina" ])
    expect(Medication.find_by(name: "CIPROBETA").substances.map(&:name)).to eq([ "ciprofloxacina" ])
    expect(Medication.find_by(name: "DORLESS").effective_sncr_type).to eq("RCE")

    # Associação num campo só: casa o que existe na base e ignora o resto.
    expect(Medication.find_by(name: "PARKIGAMA").substances.map(&:name)).to eq([ "levodopa" ])
  end

  it "deixa sem vínculo o princípio ativo que só se parece com a base e o manda para revisão" do
    result = import

    expect(Medication.find_by(name: "QUEIMALFA").substances).to be_empty

    review = CSV.read(review_path, headers: true).map { |row| row.to_h }
    entry = review.find { |row| row["principio_ativo"] == "SULFADIAZINA DE PRATA" }
    expect(entry).to include("motivo" => "quase_casamento", "substancia_sugerida" => "sulfadiazina")
    expect(result[:review]).to be_present
  end

  it "é idempotente: reexecutar não duplica, não altera e não recria vínculo" do
    first = import
    second = import

    expect(first[:created]).to eq(9)
    expect(second).to include(created: 0, updated: 0, unchanged: 9, links_created: 0)
    expect(Medication.count).to eq(9)
    expect(MedicationSubstance.count).to eq(first[:links_created])
  end

  it "não reverte desativação nem apaga vínculo feito no back-office" do
    import
    medication = Medication.find_by(name: "DORLESS")
    medication.update!(active: false, default_posology: "1 cápsula de 8/8h")
    Medication.find_by(name: "DORALFA").substances << Substance.find_by(name: "tramadol")

    import

    expect(medication.reload).to have_attributes(active: false, default_posology: "1 cápsula de 8/8h")
    expect(Medication.find_by(name: "DORALFA").substances.map(&:name)).to eq([ "tramadol" ])
  end

  it "casa cadastro manual do back-office pelo EAN em vez de duplicar" do
    manual = Medication.create!(name: "Dorless (cadastro manual)", ean: "7891000000011")

    import

    expect(Medication.count).to eq(9)
    expect(manual.reload).to have_attributes(name: "DORLESS", anvisa_registration: "1234500010011")
  end

  it "recusa arquivo sem o cabeçalho da lista" do
    other = Rails.root.join("tmp/spec_cmed_invalido.csv")
    File.write(other, "coluna;outra\n1;2\n")

    expect { described_class.call(path: other, io: io, review_path: review_path) }
      .to raise_error(described_class::Error, /Cabeçalho/)
  ensure
    FileUtils.rm_f(other)
  end
end
