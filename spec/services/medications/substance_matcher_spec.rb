require "rails_helper"

RSpec.describe Medications::SubstanceMatcher do
  subject(:matcher) { described_class.new }

  before do
    Substance.create!(name: "tramadol", list_344: "C1", sncr_type: "RCE")
    Substance.create!(name: "amoxicilina", list_344: "IN 360/2025 art. 1º (antimicrobiano)", sncr_type: "RET")
    Substance.create!(name: "ciprofloxacina", list_344: "IN 360/2025 art. 1º (antimicrobiano)", sncr_type: "RET")
    Substance.create!(name: "sulfadiazina", list_344: "IN 360/2025 art. 1º (antimicrobiano)", sncr_type: "RET")
    Substance.create!(name: "valproato sódico", list_344: "C1", sncr_type: "RCE")
    Substance.create!(name: "ftalimidoglutarimida (talidomida)", list_344: "C3", sncr_type: "NRT")
    Substance.create!(name: "metandienona ou metandrostenolona", list_344: "C5", sncr_type: "RCE")
  end

  it "casa o nome publicado como está" do
    expect(matcher.match("AMOXICILINA")&.name).to eq("amoxicilina")
  end

  it "desfaz o sal do prefixo e o grau de hidratação" do
    expect(matcher.match("CLORIDRATO DE TRAMADOL")&.name).to eq("tramadol")
    expect(matcher.match("AMOXICILINA TRI-HIDRATADA")&.name).to eq("amoxicilina")
    expect(matcher.match("CLORIDRATO DE CIPROFLOXACINA MONOIDRATADO")&.name).to eq("ciprofloxacina")
  end

  it "aceita a variação de gênero entre a CMED e o Anexo I" do
    expect(matcher.match("CIPROFLOXACINO")&.name).to eq("ciprofloxacina")
  end

  it "converte o contraíon 'de sódio' no adjetivo usado pela 344/98" do
    expect(matcher.match("VALPROATO DE SÓDIO")&.name).to eq("valproato sódico")
  end

  it "casa os sinônimos guardados no próprio nome da substância" do
    expect(matcher.match("TALIDOMIDA")&.name).to eq("ftalimidoglutarimida (talidomida)")
    expect(matcher.match("METANDROSTENOLONA")&.name).to eq("metandienona ou metandrostenolona")
  end

  it "não casa princípio ativo apenas parecido, mas aponta a suspeita" do
    expect(matcher.match("SULFADIAZINA DE PRATA")).to be_nil
    expect(matcher.near_miss("SULFADIAZINA DE PRATA")).to eq("sulfadiazina")
  end

  it "não inventa casamento para substância fora da base" do
    expect(matcher.match("DIPIRONA MONOIDRATADA")).to be_nil
    expect(matcher.near_miss("DIPIRONA MONOIDRATADA")).to be_nil
  end

  it "quebra a associação que a CMED publica num campo só" do
    ingredients = described_class.split_ingredients("LEVODOPA;CARBIDOPA (PORT. 344/98 LISTA C 1)")

    expect(ingredients).to eq([ "LEVODOPA", "CARBIDOPA" ])
  end
end
