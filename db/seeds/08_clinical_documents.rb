# frozen_string_literal: true

def seed_clinical_documents!(context)
  clinic = context.fetch(:clinic)
  second_clinic = context.fetch(:second_clinic)
  hospital = context.fetch(:hospital)
  doctor = context.fetch(:doctor)
  hospital_doctor = context.fetch(:hospital_doctor)
  mariana = context.fetch(:mariana)
  carlos = context.fetch(:carlos)
  luciana = context.fetch(:luciana)
  fernanda = context.fetch(:fernanda)
  roberto = context.fetch(:roberto)
  julia = context.fetch(:julia)
  patricia = context.fetch(:patricia)
  eduardo = context.fetch(:eduardo)

  prescription = upsert_by(
    Prescription,
    { code: "RX-SEED-0001" },
    {
      patient: mariana,
      user: doctor,
      organization: clinic,
      content: "Dipirona 500mg, tomar 1 comprimido a cada 6 horas se dor ou febre.",
      issued_on: Date.current,
      valid_until: Date.current + 30.days,
      status: "draft"
    }
  )

  second_prescription = upsert_by(
    Prescription,
    { code: "RX-SEED-0002" },
    {
      patient: carlos,
      user: doctor,
      organization: clinic,
      content: "Ibuprofeno 400mg, tomar 1 comprimido a cada 8 horas por ate 3 dias.",
      issued_on: Date.current - 2.days,
      valid_until: Date.current + 15.days,
      status: "draft"
    }
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

  third_prescription = upsert_by(
    Prescription,
    { code: "RX-SEED-0003" },
    {
      patient: fernanda,
      user: doctor,
      organization: clinic,
      content: "Losartana 50mg, tomar 1 comprimido pela manha por 30 dias.",
      issued_on: Date.current,
      valid_until: Date.current + 60.days,
      status: "draft"
    }
  )

  hospital_prescription = upsert_by(
    Prescription,
    { code: "RX-SEED-0004" },
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

  second_clinic_prescription = upsert_by(
    Prescription,
    { code: "RX-SEED-0005" },
    {
      patient: patricia,
      user: doctor,
      organization: second_clinic,
      content: "Hidroclorotiazida 25mg, tomar 1 comprimido pela manha por 30 dias.",
      issued_on: Date.current,
      valid_until: Date.current + 45.days,
      status: "draft"
    }
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

  sent_prescription = upsert_by(
    Prescription,
    { code: "RX-SEED-0006" },
    {
      patient: mariana,
      user: doctor,
      organization: clinic,
      content: "Cetirizina 10mg, tomar 1 comprimido a noite por 5 dias.",
      issued_on: Date.current - 1.day,
      valid_until: Date.current + 20.days,
      status: "signed"
    }
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
    sent_prescription: sent_prescription
  }
end
