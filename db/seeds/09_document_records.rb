# frozen_string_literal: true

def seed_document_records!(context)
  clinic = context.fetch(:clinic)
  second_clinic = context.fetch(:second_clinic)
  hospital = context.fetch(:hospital)
  clinic_default_unit = context.fetch(:clinic_default_unit)
  clinic_lab_unit = context.fetch(:clinic_lab_unit)
  second_clinic_default_unit = context.fetch(:second_clinic_default_unit)
  hospital_default_unit = context.fetch(:hospital_default_unit)
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
  prescription = context.fetch(:prescription)
  second_prescription = context.fetch(:second_prescription)
  certificate = context.fetch(:certificate)
  hospital_certificate = context.fetch(:hospital_certificate)
  third_prescription = context.fetch(:third_prescription)
  hospital_prescription = context.fetch(:hospital_prescription)
  cancelled_certificate = context.fetch(:cancelled_certificate)
  second_clinic_prescription = context.fetch(:second_clinic_prescription)
  second_clinic_certificate = context.fetch(:second_clinic_certificate)
  sent_prescription = context.fetch(:sent_prescription)

  documents = [
    {
      key: { code: "DOC-RX-SEED-0001" },
      attrs: {
        patient: mariana,
        user: doctor,
        organization: clinic,
        unit: clinic_default_unit,
        documentable: prescription,
        kind: "prescription",
        status: "issued",
        current_version: 1,
        issued_on: prescription.issued_on,
        metadata: { seed: true, channel: "email" }
      }
    },
    {
      key: { code: "DOC-RX-SEED-0002" },
      attrs: {
        patient: carlos,
        user: doctor,
        organization: clinic,
        unit: clinic_lab_unit,
        documentable: second_prescription,
        kind: "prescription",
        status: "issued",
        current_version: 1,
        issued_on: second_prescription.issued_on,
        metadata: { seed: true, channel: "manual" }
      }
    },
    {
      key: { code: "DOC-MC-SEED-0001" },
      attrs: {
        patient: carlos,
        user: doctor,
        organization: clinic,
        unit: clinic_default_unit,
        documentable: certificate,
        kind: "medical_certificate",
        status: "issued",
        current_version: 1,
        issued_on: certificate.issued_on,
        metadata: { seed: true, channel: "whatsapp" }
      }
    },
    {
      key: { code: "DOC-MC-SEED-0002" },
      attrs: {
        patient: luciana,
        user: hospital_doctor,
        organization: hospital,
        unit: hospital_default_unit,
        documentable: hospital_certificate,
        kind: "medical_certificate",
        status: "issued",
        current_version: 1,
        issued_on: hospital_certificate.issued_on,
        metadata: { seed: true, channel: "manual" }
      }
    },
    {
      key: { code: "DOC-RX-SEED-0003" },
      attrs: {
        patient: fernanda,
        user: doctor,
        organization: clinic,
        unit: clinic_default_unit,
        documentable: third_prescription,
        kind: "prescription",
        status: "issued",
        current_version: 1,
        issued_on: third_prescription.issued_on,
        metadata: { seed: true, channel: "email" }
      }
    },
    {
      key: { code: "DOC-RX-SEED-0004" },
      attrs: {
        patient: roberto,
        user: hospital_doctor,
        organization: hospital,
        unit: hospital_default_unit,
        documentable: hospital_prescription,
        kind: "prescription",
        status: "issued",
        current_version: 1,
        issued_on: hospital_prescription.issued_on,
        metadata: { seed: true, channel: "sms" }
      }
    },
    {
      key: { code: "DOC-MC-SEED-0003" },
      attrs: {
        patient: julia,
        user: doctor,
        organization: clinic,
        unit: clinic_lab_unit,
        documentable: cancelled_certificate,
        kind: "medical_certificate",
        status: "revoked",
        current_version: 1,
        issued_on: cancelled_certificate.issued_on,
        metadata: { seed: true, channel: "manual" }
      }
    },
    {
      key: { code: "DOC-RX-SEED-0005" },
      attrs: {
        patient: patricia,
        user: doctor,
        organization: second_clinic,
        unit: second_clinic_default_unit,
        documentable: second_clinic_prescription,
        kind: "prescription",
        status: "issued",
        current_version: 1,
        issued_on: second_clinic_prescription.issued_on,
        metadata: { seed: true, channel: "email", cross_clinic_doctor: true }
      }
    },
    {
      key: { code: "DOC-MC-SEED-0004" },
      attrs: {
        patient: eduardo,
        user: doctor,
        organization: second_clinic,
        unit: second_clinic_default_unit,
        documentable: second_clinic_certificate,
        kind: "medical_certificate",
        status: "issued",
        current_version: 1,
        issued_on: second_clinic_certificate.issued_on,
        metadata: { seed: true, channel: "manual", cross_clinic_doctor: true }
      }
    },
    {
      key: { code: "DOC-RX-SEED-0006" },
      attrs: {
        patient: mariana,
        user: doctor,
        organization: clinic,
        unit: clinic_default_unit,
        documentable: sent_prescription,
        kind: "prescription",
        status: "sent",
        current_version: 1,
        issued_on: sent_prescription.issued_on,
        metadata: { seed: true, channel: "email", example_state: "sent" }
      }
    }
  ].map { |entry| upsert_by(Document, entry.fetch(:key), entry.fetch(:attrs)) }

  documents.each do |document|
    content = [
      "Documento #{document.code}",
      "Paciente: #{document.patient.full_name}",
      "Tipo: #{document.kind}",
      "Conteudo: #{document.documentable.content}"
    ].join("\n")

    create_once_by(
      DocumentVersion,
      { document: document, version_number: 1 },
      {
        content: content,
        checksum: Digest::SHA256.hexdigest(content),
        generated_at: SEED_NOW,
        metadata: { seed: true, format: "text/plain" }
      }
    )
  end

  {
    documents: documents,
    sent_document: documents.first,
    viewed_document: documents.third
  }
end
