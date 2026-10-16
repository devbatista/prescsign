# A receita exige ao menos um item (Prescription#must_have_items). Para os specs
# cujo assunto não é a classificação, um item de texto livre confirmado como não
# controlado: ele não deriva tipo nenhum, então o `sncr_type` que o spec fixa à
# mão continua valendo. O nome é neutro de propósito — um nome de substância
# casaria com a base e mudaria o tipo da receita.
module PrescriptionSpecHelpers
  def spec_prescription_items(name: "Medicamento de teste")
    [ { name: name, uncontrolled_confirmed: true } ]
  end
end

RSpec.configure do |config|
  config.include PrescriptionSpecHelpers
end
