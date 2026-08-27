# frozen_string_literal: true

# Cria (ou atualiza) uma receita junto dos seus itens estruturados, num único
# save. Precisa ser num save só porque o `content` — que continua sendo a fonte
# do PDF e do checksum — é sintetizado dos itens no before_validation da receita:
# gravar a receita primeiro e anexar os itens depois esbarraria na obrigação de
# content presente. O mesmo save deriva o `sncr_type` do catálogo
# (Prescription#sync_sncr_type_from_items), então receita controlada não precisa
# declarar tipo aqui — ele sai da substância do medicamento.
#
# `items:` vazio = receita em texto livre, e aí o `content` vem em `attributes`.
def upsert_prescription!(code, attributes, items: [])
  prescription = Prescription.find_or_initialize_by(code: code)
  prescription.assign_attributes(attributes)

  items.each_with_index do |spec, index|
    position = index + 1
    item = prescription.prescription_items.detect { |candidate| candidate.position == position } ||
           prescription.prescription_items.build(position: position)
    item.assign_attributes(spec)
  end

  prescription.save!
  prescription
end

def seed_clinical_documents!(context)
  clinic = context.fetch(:clinic)
  second_clinic = context.fetch(:second_clinic)
  hospital = context.fetch(:hospital)
  doctor = context.fetch(:doctor)
  hospital_doctor = context.fetch(:hospital_doctor)
  medications = context.fetch(:medications)
  mariana = context.fetch(:mariana)
  carlos = context.fetch(:carlos)
  luciana = context.fetch(:luciana)
  fernanda = context.fetch(:fernanda)
  roberto = context.fetch(:roberto)
  julia = context.fetch(:julia)
  patricia = context.fetch(:patricia)
  eduardo = context.fetch(:eduardo)

  prescription = upsert_prescription!(
    "RX-SEED-0001",
    {
      patient: mariana,
      user: doctor,
      organization: clinic,
      issued_on: Date.current,
      valid_until: Date.current + 30.days,
      status: "draft"
    },
    items: [
      {
        medication: medications.fetch(:dipirona),
        name: "DIPIRONA MONOHIDRATADA",
        active_ingredient: "DIPIRONA MONOIDRATADA",
        strength: "500 MG",
        quantity: "1 caixa",
        posology: "Tomar 1 comprimido a cada 6 horas se dor ou febre."
      }
    ]
  )

  second_prescription = upsert_prescription!(
    "RX-SEED-0002",
    {
      patient: carlos,
      user: doctor,
      organization: clinic,
      issued_on: Date.current - 2.days,
      valid_until: Date.current + 15.days,
      status: "draft"
    },
    items: [
      {
        medication: medications.fetch(:ibuprofeno),
        name: "IBUPROFENO",
        active_ingredient: "IBUPROFENO",
        strength: "400 MG",
        quantity: "1 caixa com 10 comprimidos",
        posology: "Tomar 1 comprimido a cada 8 horas por até 3 dias."
      }
    ]
  )

  certificate = upsert_by(
    MedicalCertificate,
    { code: "MC-SEED-0001" },
    {
      patient: carlos,
      user: doctor,
      organization: clinic,
      content: "Atesto necessidade de afastamento das atividades laborais por 3 dias.",
      issued_on: Date.current,
      rest_start_on: Date.current,
      rest_end_on: Date.current + 2.days,
      icd_code: "M54.5",
      status: "draft"
    }
  )

  hospital_certificate = upsert_by(
    MedicalCertificate,
    { code: "MC-SEED-0002" },
    {
      patient: luciana,
      user: hospital_doctor,
      organization: hospital,
      content: "Atesto comparecimento para consulta medica nesta data.",
      issued_on: Date.current,
      rest_start_on: Date.current,
      rest_end_on: Date.current,
      icd_code: "R00.2",
      status: "draft"
    }
  )

  third_prescription = upsert_prescription!(
    "RX-SEED-0003",
    {
      patient: fernanda,
      user: doctor,
      organization: clinic,
      issued_on: Date.current,
      valid_until: Date.current + 60.days,
      status: "draft"
    },
    items: [
      {
        medication: medications.fetch(:losartana),
        name: "LOSARTANA POTASSICA",
        active_ingredient: "LOSARTANA POTÁSSICA",
        strength: "50 MG",
        quantity: "2 caixas com 30 comprimidos",
        posology: "Tomar 1 comprimido pela manhã por 30 dias."
      }
    ]
  )

  # Receita em texto livre (sem itens): o app continua aceitando o formato
  # antigo, e o seed mantém um exemplo dele para não perder essa cobertura.
  hospital_prescription = upsert_prescription!(
    "RX-SEED-0004",
    {
      patient: roberto,
      user: hospital_doctor,
      organization: hospital,
      content: "AAS 100mg, tomar 1 comprimido ao dia apos avaliacao medica.",
      issued_on: Date.current - 1.day,
      valid_until: Date.current + 30.days,
      status: "draft"
    }
  )

  cancelled_certificate = upsert_by(
    MedicalCertificate,
    { code: "MC-SEED-0003" },
    {
      patient: julia,
      user: doctor,
      organization: clinic,
      content: "Atestado cancelado apos revisao administrativa.",
      issued_on: Date.current - 3.days,
      rest_start_on: Date.current - 3.days,
      rest_end_on: Date.current - 2.days,
      icd_code: "Z00.0",
      status: "cancelled"
    }
  )

  second_clinic_prescription = upsert_prescription!(
    "RX-SEED-0005",
    {
      patient: patricia,
      user: doctor,
      organization: second_clinic,
      issued_on: Date.current,
      valid_until: Date.current + 45.days,
      status: "draft"
    },
    items: [
      {
        medication: medications.fetch(:hidroclorotiazida),
        name: "HIDROCLOROTIAZIDA",
        active_ingredient: "HIDROCLOROTIAZIDA",
        strength: "25 MG",
        quantity: "1 caixa com 30 comprimidos",
        posology: "Tomar 1 comprimido pela manhã por 30 dias."
      }
    ]
  )

  second_clinic_certificate = upsert_by(
    MedicalCertificate,
    { code: "MC-SEED-0004" },
    {
      patient: eduardo,
      user: doctor,
      organization: second_clinic,
      content: "Atesto comparecimento para consulta na unidade Zona Sul.",
      issued_on: Date.current - 4.days,
      rest_start_on: Date.current - 4.days,
      rest_end_on: Date.current - 4.days,
      icd_code: "J30.9",
      status: "draft"
    }
  )

  # Receita com mais de um item, para exercitar a lista do formulário e do PDF.
  sent_prescription = upsert_prescription!(
    "RX-SEED-0006",
    {
      patient: mariana,
      user: doctor,
      organization: clinic,
      issued_on: Date.current - 1.day,
      valid_until: Date.current + 20.days,
      status: "signed"
    },
    items: [
      {
        medication: medications.fetch(:levocetirizina),
        name: "DICLORIDRATO DE LEVOCETIRIZINA",
        active_ingredient: "DICLORIDRATO DE LEVOCETIRIZINA",
        strength: "5 MG",
        quantity: "1 caixa com 10 comprimidos",
        posology: "Tomar 1 comprimido à noite por 5 dias."
      },
      {
        medication: medications.fetch(:dipirona),
        name: "DIPIRONA MONOHIDRATADA",
        active_ingredient: "DIPIRONA MONOIDRATADA",
        strength: "500 MG",
        quantity: "1 caixa",
        posology: "Tomar 1 comprimido a cada 6 horas se dor ou febre."
      }
    ]
  )

  # Receitas controladas: o tipo SNCR não é escolhido aqui — sai da substância do
  # medicamento no save (amitriptilina, C1 -> RCE; clonazepam, B1 -> NRB). A de
  # RCE fica em rascunho de propósito, para exercitar a assinatura consumindo o
  # pool de numeração semeado em 16_sncr_numberings.rb.
  controlled_prescription = upsert_prescription!(
    "RX-SEED-0007",
    {
      patient: julia,
      user: doctor,
      organization: clinic,
      issued_on: Date.current,
      valid_until: Date.current + 30.days,
      status: "draft"
    },
    items: [
      {
        medication: medications.fetch(:amitriptilina),
        name: "AMYTRIL",
        active_ingredient: "CLORIDRATO DE AMITRIPTILINA",
        strength: "25 MG",
        quantity: "1 caixa com 20 comprimidos",
        posology: "Tomar 1 comprimido à noite por 30 dias."
      }
    ]
  )

  signed_controlled_prescription = upsert_prescription!(
    "RX-SEED-0008",
    {
      patient: carlos,
      user: doctor,
      organization: clinic,
      issued_on: Date.current - 1.day,
      valid_until: Date.current + 30.days,
      status: "signed"
    },
    items: [
      {
        medication: medications.fetch(:clonazepam),
        name: "CLONAZEPAM",
        active_ingredient: "CLONAZEPAM",
        strength: "2 MG",
        quantity: "1 caixa com 20 comprimidos",
        posology: "Tomar 1 comprimido à noite."
      }
    ]
  )

  {
    prescription: prescription,
    second_prescription: second_prescription,
    certificate: certificate,
    hospital_certificate: hospital_certificate,
    third_prescription: third_prescription,
    hospital_prescription: hospital_prescription,
    cancelled_certificate: cancelled_certificate,
    second_clinic_prescription: second_clinic_prescription,
    second_clinic_certificate: second_clinic_certificate,
    sent_prescription: sent_prescription,
    controlled_prescription: controlled_prescription,
    signed_controlled_prescription: signed_controlled_prescription
  }
end
