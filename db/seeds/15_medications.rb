# frozen_string_literal: true

# Recorte de demonstração do catálogo de medicamentos. O catálogo de verdade vem
# da Lista de Preços da CMED (`rake medications:import`, ~25 mil apresentações),
# que não é versionada no repo e que o `reset_seed_data!` trunca junto com o
# resto — sem este recorte, a busca de medicamento do formulário de receita volta
# vazia logo depois de semear (ver docs/sncr/SUBSTANCES_DATA_SOURCING.md §8).
#
# As linhas são reais: produto, princípio ativo, registro Anvisa, EAN, tarja e
# apresentação como a CMED publica. Isso importa porque a chave da carga oficial
# é o registro Anvisa (EAN como alternativa) — rodar `medications:import` depois
# do seed atualiza estes mesmos produtos em vez de duplicá-los.
#
# A seleção cobre uma prescrição comum e um representante de cada tipo de
# receituário controlado que o app trata hoje: RCE (C1), NRB (B1), NRR (C2) e
# RET (antimicrobiano). O tipo não é declarado aqui — sai da substância, via
# Medication#effective_sncr_type.
DEMO_MEDICATIONS = [
  {
    key: :dipirona,
    name: "DIPIRONA MONOHIDRATADA",
    active_ingredient: "DIPIRONA MONOIDRATADA",
    strength: "500 MG",
    pharmaceutical_form: "comprimido",
    control_class: "comum",
    anvisa_registration: "1677305860080",
    ean: "7894916143226",
    manufacturer: "LEGRAND PHARMA INDUSTRIA FARMACEUTICA LTDA",
    presentation: "500 MG COM CT BL AL PLAS PVC TRANS X 240",
    default_posology: "Tomar 1 comprimido a cada 6 horas se dor ou febre."
  },
  {
    key: :ibuprofeno,
    name: "IBUPROFENO",
    active_ingredient: "IBUPROFENO",
    strength: "400 MG",
    pharmaceutical_form: "comprimido",
    control_class: "comum",
    anvisa_registration: "1256803200017",
    ean: "7899547512748",
    manufacturer: "PRATI DONADUZZI & CIA LTDA",
    presentation: "400 MG COM REV CT BL AL PLAS PVC TRANS X 10",
    default_posology: "Tomar 1 comprimido a cada 8 horas por até 3 dias."
  },
  {
    key: :losartana,
    name: "LOSARTANA POTASSICA",
    active_ingredient: "LOSARTANA POTÁSSICA",
    strength: "50 MG",
    pharmaceutical_form: "comprimido",
    control_class: "tarja_vermelha",
    anvisa_registration: "1558404280159",
    ean: "7896714208565",
    manufacturer: "BRAINFARMA INDÚSTRIA QUÍMICA E FARMACÊUTICA S.A",
    presentation: "50 MG COM REV CT BL AL PLAS OPC X 30",
    default_posology: "Tomar 1 comprimido pela manhã."
  },
  {
    key: :hidroclorotiazida,
    name: "HIDROCLOROTIAZIDA",
    active_ingredient: "HIDROCLOROTIAZIDA",
    strength: "25 MG",
    pharmaceutical_form: "comprimido",
    control_class: "tarja_vermelha",
    anvisa_registration: "1023507920151",
    ean: "7896004716176",
    manufacturer: "EMS S/A",
    presentation: "25 MG COM CT BL AL PLAS OPC X 30",
    default_posology: "Tomar 1 comprimido pela manhã."
  },
  {
    key: :aas,
    name: "ACIDO ACETILSALICILICO",
    active_ingredient: "ÁCIDO ACETILSALICÍLICO",
    strength: "100 MG",
    pharmaceutical_form: "comprimido",
    control_class: "comum",
    anvisa_registration: "1023505080197",
    ean: "7896004710891",
    manufacturer: "EMS S/A",
    presentation: "100 MG COM CT BL AL PLAS PVC OPC X 30",
    default_posology: "Tomar 1 comprimido ao dia após avaliação médica."
  },
  {
    key: :levocetirizina,
    name: "DICLORIDRATO DE LEVOCETIRIZINA",
    active_ingredient: "DICLORIDRATO DE LEVOCETIRIZINA",
    strength: "5 MG",
    pharmaceutical_form: "comprimido",
    control_class: "comum",
    anvisa_registration: "1023513750031",
    ean: "7896004757353",
    manufacturer: "EMS S/A",
    presentation: "5 MG COM REV CT BL AL AL X 10",
    default_posology: "Tomar 1 comprimido à noite por 5 dias."
  },
  {
    # Antimicrobiano: RET (Receita Sujeita a Retenção), IN 360/2025 art. 1º.
    key: :amoxicilina,
    name: "AMOXICILINA",
    active_ingredient: "AMOXICILINA",
    strength: "500 MG",
    pharmaceutical_form: "capsula",
    control_class: "tarja_vermelha_retencao",
    anvisa_registration: "1037004470189",
    ean: "7896112192060",
    manufacturer: "LABORATORIO TEUTO BRASILEIRO S/A",
    presentation: "500 MG CAP DURA CT BL AL PLAS PVC/PVDC TRANS X 500",
    default_posology: "Tomar 1 cápsula a cada 8 horas por 7 dias."
  },
  {
    # Lista C1 -> RCE (Receita de Controle Especial).
    key: :amitriptilina,
    name: "AMYTRIL",
    active_ingredient: "CLORIDRATO DE AMITRIPTILINA",
    strength: "25 MG",
    pharmaceutical_form: "comprimido",
    control_class: "tarja_vermelha_retencao",
    anvisa_registration: "1029802250045",
    ean: "7896676400083",
    manufacturer: "CRISTÁLIA PRODUTOS QUÍMICOS FARMACÊUTICOS LTDA.",
    presentation: "25 MG COM REV CT BL AL PLAS PVDC TRANS X 20",
    default_posology: "Tomar 1 comprimido à noite."
  },
  {
    # Lista B1 -> NRB (Notificação de Receita B).
    key: :clonazepam,
    name: "CLONAZEPAM",
    active_ingredient: "CLONAZEPAM",
    strength: "2 MG",
    pharmaceutical_form: "comprimido",
    control_class: "tarja_preta",
    anvisa_registration: "1058308360017",
    ean: "7896004721835",
    manufacturer: "GERMED FARMACEUTICA LTDA",
    presentation: "2 MG COM CT BL AL PLAS PVDC OPC X 20",
    default_posology: "Tomar 1 comprimido à noite."
  },
  {
    # Lista C2 (retinoide) -> NRR (Notificação de Receita Especial).
    key: :isotretinoina,
    name: "ACNOVA",
    active_ingredient: "ISOTRETINOÍNA",
    strength: "20 MG",
    pharmaceutical_form: "capsula",
    control_class: "tarja_vermelha_retencao",
    anvisa_registration: "1058308440096",
    ean: "7896004734064",
    manufacturer: "GERMED FARMACEUTICA LTDA",
    presentation: "20 MG CAP MOLE CT BL AL/AL X 30",
    default_posology: "Tomar 1 cápsula ao dia junto com uma refeição."
  }
].freeze

# Carrega o recorte e liga cada produto às substâncias controladas pelo mesmo
# casamento exato da carga oficial (Medications::SubstanceMatcher) — princípio
# ativo que não casa fica sem vínculo, como lá, em vez de virar palpite.
def seed_medications!
  matcher = Medications::SubstanceMatcher.new

  medications = DEMO_MEDICATIONS.to_h do |spec|
    attributes = spec.except(:key)
    medication = upsert_by(
      Medication,
      { anvisa_registration: attributes.fetch(:anvisa_registration) },
      attributes.merge(active: true)
    )

    Medications::SubstanceMatcher
      .split_ingredients(medication.active_ingredient)
      .filter_map { |ingredient| matcher.match(ingredient) }
      .each { |substance| upsert_by(MedicationSubstance, { medication: medication, substance: substance }, {}) }

    [ spec.fetch(:key), medication ]
  end

  { medications: medications }
end
