# frozen_string_literal: true

# Especialidades médicas reconhecidas pela Comissão Mista de Especialidades
# (CFM/AMB/CNRM), conforme Resolução CFM nº 2.330/2023, que homologa a
# Portaria CME nº 1/2023.
SEED_SPECIALTY_NAMES = [
  "Acupuntura",
  "Alergia e Imunologia",
  "Anestesiologia",
  "Angiologia",
  "Cardiologia",
  "Cirurgia Cardiovascular",
  "Cirurgia da Mão",
  "Cirurgia de Cabeça e Pescoço",
  "Cirurgia do Aparelho Digestivo",
  "Cirurgia Geral",
  "Cirurgia Oncológica",
  "Cirurgia Pediátrica",
  "Cirurgia Plástica",
  "Cirurgia Torácica",
  "Cirurgia Vascular",
  "Clínica Médica",
  "Coloproctologia",
  "Dermatologia",
  "Endocrinologia e Metabologia",
  "Endoscopia",
  "Gastroenterologia",
  "Genética Médica",
  "Geriatria",
  "Ginecologia e Obstetrícia",
  "Hematologia e Hemoterapia",
  "Homeopatia",
  "Infectologia",
  "Mastologia",
  "Medicina de Emergência",
  "Medicina de Família e Comunidade",
  "Medicina do Trabalho",
  "Medicina de Tráfego",
  "Medicina Esportiva",
  "Medicina Física e Reabilitação",
  "Medicina Intensiva",
  "Medicina Legal e Perícia Médica",
  "Medicina Nuclear",
  "Medicina Preventiva e Social",
  "Nefrologia",
  "Neurocirurgia",
  "Neurologia",
  "Nutrologia",
  "Oftalmologia",
  "Oncologia Clínica",
  "Ortopedia e Traumatologia",
  "Otorrinolaringologia",
  "Patologia",
  "Patologia Clínica/Medicina Laboratorial",
  "Pediatria",
  "Pneumologia",
  "Psiquiatria",
  "Radiologia e Diagnóstico por Imagem",
  "Radioterapia",
  "Reumatologia",
  "Urologia"
].freeze

def seed_specialties!
  SEED_SPECIALTY_NAMES.index_with do |name|
    specialty = Specialty.find_or_create_by_name!(name)
    specialty.update!(active: true) unless specialty.active?
    specialty
  end
end
