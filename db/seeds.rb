# frozen_string_literal: true

require "digest"

SEED_PASSWORD = ENV.fetch("SEED_PASSWORD", "password123")
SEED_NOW = Time.zone.parse("2026-05-11 09:00:00")

def upsert_by(model, lookup, attributes)
  record = model.find_or_initialize_by(lookup)
  record.assign_attributes(attributes)
  record.save!
  record
end

def create_once_by(model, lookup, attributes)
  record = model.find_or_initialize_by(lookup)
  return record if record.persisted?

  record.assign_attributes(attributes)
  record.save!
  record
end

ActiveRecord::Base.transaction do
  clinic = upsert_by(
    Organization,
    { cnpj: "12345678000190" },
    {
      kind: "clinica",
      legal_name: "PrescSign Clinica Medica LTDA",
      trade_name: "PrescSign Clinica",
      name: "PrescSign Clinica",
      email: "contato@prescsign.test",
      phone: "1133334444",
      zip_code: "01310930",
      street: "Avenida Paulista",
      number: "1000",
      complement: "Conjunto 1201",
      district: "Bela Vista",
      city: "Sao Paulo",
      state: "SP",
      country: "BR",
      active: true,
      metadata: { seed: true, plan: "demo" }
    }
  )

  hospital = upsert_by(
    Organization,
    { cnpj: "98765432000110" },
    {
      kind: "hospital",
      legal_name: "Hospital Vida Digital SA",
      trade_name: "Hospital Vida Digital",
      name: "Hospital Vida Digital",
      email: "operacoes@hospitalvida.test",
      phone: "2132225500",
      zip_code: "22250040",
      street: "Rua Voluntarios da Patria",
      number: "250",
      district: "Botafogo",
      city: "Rio de Janeiro",
      state: "RJ",
      country: "BR",
      active: true,
      metadata: { seed: true, plan: "enterprise" }
    }
  )

  clinic_default_unit = clinic.default_unit
  clinic_default_unit.update!(name: "Unidade Paulista", code: "PAULISTA", active: true)

  clinic_lab_unit = upsert_by(
    Unit,
    { organization: clinic, name: "Unidade Jardins" },
    { code: "JARDINS", active: true }
  )

  hospital_default_unit = hospital.default_unit
  hospital_default_unit.update!(name: "Pronto Atendimento", code: "PA", active: true)

  admin = upsert_by(
    User,
    { email: "admin@prescsign.test" },
    {
      password: SEED_PASSWORD,
      password_confirmation: SEED_PASSWORD,
      status: "active",
      confirmed_at: SEED_NOW,
      current_organization: clinic
    }
  )

  doctor = upsert_by(
    User,
    { email: "medico@prescsign.test" },
    {
      password: SEED_PASSWORD,
      password_confirmation: SEED_PASSWORD,
      status: "active",
      confirmed_at: SEED_NOW,
      current_organization: clinic
    }
  )

  staff = upsert_by(
    User,
    { email: "recepcao@prescsign.test" },
    {
      password: SEED_PASSWORD,
      password_confirmation: SEED_PASSWORD,
      status: "active",
      confirmed_at: SEED_NOW,
      current_organization: clinic
    }
  )

  hospital_doctor = upsert_by(
    User,
    { email: "hospital.medico@prescsign.test" },
    {
      password: SEED_PASSWORD,
      password_confirmation: SEED_PASSWORD,
      status: "active",
      confirmed_at: SEED_NOW,
      current_organization: hospital
    }
  )

  [
    [admin, "admin"],
    [doctor, "doctor"],
    [staff, "support"],
    [hospital_doctor, "doctor"]
  ].each do |user, role|
    upsert_by(UserRole, { user: user, role: role }, { status: "active" })
  end

  [
    [admin, clinic, "owner"],
    [doctor, clinic, "doctor"],
    [staff, clinic, "staff"],
    [hospital_doctor, hospital, "doctor"]
  ].each do |user, organization, role|
    upsert_by(
      OrganizationMembership,
      { user: user, organization: organization },
      { role: role, status: "active" }
    )
  end

  upsert_by(OrganizationResponsible, { organization: clinic, user: admin }, {})
  upsert_by(OrganizationResponsible, { organization: hospital, user: hospital_doctor }, {})

  upsert_by(
    DoctorProfile,
    { user: doctor },
    {
      full_name: "Dra. Ana Beatriz Costa",
      cpf: "11122233344",
      email: doctor.email,
      license_number: "CRM123456",
      license_state: "SP",
      specialty: "Clinica Geral",
      gender: "female",
      active: true
    }
  )

  upsert_by(
    DoctorProfile,
    { user: hospital_doctor },
    {
      full_name: "Dr. Rafael Martins",
      cpf: "22233344455",
      email: hospital_doctor.email,
      license_number: "CRM654321",
      license_state: "RJ",
      specialty: "Cardiologia",
      gender: "male",
      active: true
    }
  )

  patients = [
    {
      key: { organization: clinic, cpf: "33344455566" },
      attrs: {
        user: doctor,
        full_name: "Mariana Almeida",
        birth_date: Date.new(1988, 4, 15),
        email: "mariana.almeida@example.test",
        phone: "11987654321",
        active: true
      }
    },
    {
      key: { organization: clinic, cpf: "44455566677" },
      attrs: {
        user: doctor,
        full_name: "Carlos Henrique Souza",
        birth_date: Date.new(1976, 9, 3),
        email: "carlos.souza@example.test",
        phone: "11976543210",
        active: true
      }
    },
    {
      key: { organization: hospital, cpf: "55566677788" },
      attrs: {
        user: hospital_doctor,
        full_name: "Luciana Ferreira",
        birth_date: Date.new(1992, 12, 20),
        email: "luciana.ferreira@example.test",
        phone: "21999998888",
        active: true
      }
    }
  ].map { |entry| upsert_by(Patient, entry.fetch(:key), entry.fetch(:attrs)) }

  mariana, carlos, luciana = patients

  consultations = [
    {
      key: { patient: mariana, user: doctor, scheduled_at: SEED_NOW + 1.day },
      attrs: {
        organization: clinic,
        status: "scheduled",
        chief_complaint: "Cefaleia recorrente",
        notes: "Retorno agendado com diario de sintomas.",
        metadata: { source: "seed", room: "201" }
      }
    },
    {
      key: { patient: carlos, user: doctor, scheduled_at: SEED_NOW - 2.days },
      attrs: {
        organization: clinic,
        status: "completed",
        finished_at: SEED_NOW - 2.days + 35.minutes,
        chief_complaint: "Dor lombar",
        diagnosis: "Lombalgia mecanica",
        notes: "Orientado repouso relativo e retorno se piora.",
        metadata: { source: "seed", room: "203" }
      }
    },
    {
      key: { patient: luciana, user: hospital_doctor, scheduled_at: SEED_NOW + 2.days },
      attrs: {
        organization: hospital,
        status: "scheduled",
        chief_complaint: "Palpitacoes",
        notes: "Solicitado acompanhamento cardiologico.",
        metadata: { source: "seed", priority: "routine" }
      }
    }
  ].map { |entry| upsert_by(Consultation, entry.fetch(:key), entry.fetch(:attrs)) }

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
      status: "signed"
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
      status: "signed"
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
        status: "sent",
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
        status: "viewed",
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

  sent_document = documents.first
  viewed_document = documents.third

  upsert_by(
    DeliveryLog,
    { idempotency_key: "seed-delivery-email-0001" },
    {
      document: sent_document,
      patient: sent_document.patient,
      user: doctor,
      organization: clinic,
      channel: "email",
      status: "delivered",
      attempt_number: 1,
      provider_name: "seed-mailer",
      provider_message_id: "seed-msg-0001",
      recipient: sent_document.patient.email,
      attempted_at: SEED_NOW + 5.minutes,
      delivered_at: SEED_NOW + 6.minutes,
      request_id: "seed-request-email-0001",
      metadata: { seed: true }
    }
  )

  upsert_by(
    DeliveryLog,
    { idempotency_key: "seed-delivery-whatsapp-0001" },
    {
      document: viewed_document,
      patient: viewed_document.patient,
      user: doctor,
      organization: clinic,
      channel: "whatsapp",
      status: "failed",
      attempt_number: 2,
      provider_name: "seed-whatsapp",
      recipient: viewed_document.patient.phone,
      error_code: "seed_provider_unavailable",
      error_message: "Simulated provider outage for demo data",
      attempted_at: SEED_NOW + 10.minutes,
      request_id: "seed-request-whatsapp-0001",
      metadata: { seed: true, retryable: true }
    }
  )

  create_once_by(
    IdempotencyKey,
    {
      user: doctor,
      organization: clinic,
      scope: "POST /v1/prescriptions",
      key: "seed-idempotency-prescription-0001"
    },
    {
      request_fingerprint: Digest::SHA256.hexdigest("seed-prescription-request"),
      status_code: 201,
      response_body: { id: prescription.id, code: prescription.code }
    }
  )

  create_once_by(
    AuthRefreshToken,
    { token_digest: Digest::SHA256.hexdigest("seed-refresh-token") },
    { user: doctor, expires_at: 30.days.from_now }
  )

  create_once_by(
    OrganizationRegistrationInvitation,
    {
      organization: clinic,
      invited_email: "novo.medico@prescsign.test"
    },
    {
      invited_by_user: admin,
      token_digest: OrganizationRegistrationInvitation.digest_token("seed-invitation-token"),
      expires_at: 7.days.from_now
    }
  )

  [
    [prescription, "created", prescription.patient, prescription.document],
    [prescription.document, "sent", prescription.patient, prescription.document],
    [certificate.document, "viewed", certificate.patient, certificate.document],
    [consultations.second, "updated", consultations.second.patient, nil]
  ].each do |resource, action, patient, document|
    create_once_by(
      AuditLog,
      {
        resource: resource,
        action: action,
        request_id: "seed-audit-#{resource.class.name.underscore}-#{action}"
      },
      {
        actor: doctor,
        user: doctor,
        organization: patient.organization,
        unit: document&.unit || patient.organization.default_unit,
        patient: patient,
        document: document,
        before_data: {},
        after_data: { seed: true, action: action },
        request_origin: "seed",
        ip_address: "127.0.0.1",
        user_agent: "db/seeds.rb",
        occurred_at: SEED_NOW
      }
    )
  end
end

puts "Seed complete."
puts "Demo users:"
puts "  admin@prescsign.test / #{SEED_PASSWORD}"
puts "  medico@prescsign.test / #{SEED_PASSWORD}"
puts "  recepcao@prescsign.test / #{SEED_PASSWORD}"
puts "  hospital.medico@prescsign.test / #{SEED_PASSWORD}"
