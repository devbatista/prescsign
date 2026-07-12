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

def sync_user_roles(user, active_roles)
  active_roles = active_roles.map(&:to_s)
  user.user_roles.where.not(role: active_roles).update_all(status: "inactive", updated_at: Time.current)

  active_roles.each do |role|
    upsert_by(UserRole, { user: user, role: role }, { status: "active" })
  end
end

def reset_seed_data!
  connection = ActiveRecord::Base.connection
  ignored_tables = %w[ar_internal_metadata schema_migrations]
  tables = connection.tables - ignored_tables
  return if tables.empty?

  quoted_tables = tables.map { |table| connection.quote_table_name(table) }.join(", ")
  connection.execute("TRUNCATE TABLE #{quoted_tables} RESTART IDENTITY CASCADE")
end

def seed_digits(key, length)
  digest = Digest::SHA256.hexdigest("prescsign-seed-#{key}")
  digest.chars.map { |char| char.to_i(16).to_s }.join.first(length)
end

def cpf_check_digit(numbers)
  sum = numbers.each_with_index.sum { |digit, index| digit * (numbers.length + 1 - index) }
  remainder = (sum * 10) % 11
  remainder == 10 ? 0 : remainder
end

def seed_cpf(key)
  digits = seed_digits("cpf-#{key}", 9).chars.map(&:to_i)
  first_digit = cpf_check_digit(digits)
  second_digit = cpf_check_digit(digits + [first_digit])
  (digits + [first_digit, second_digit]).join
end

def cnpj_check_digit(numbers, weights)
  remainder = numbers.zip(weights).sum { |digit, weight| digit * weight } % 11
  remainder < 2 ? 0 : 11 - remainder
end

def seed_cnpj(key)
  digits = seed_digits("cnpj-#{key}", 8).chars.map(&:to_i) + [0, 0, 0, 1]
  first_digit = cnpj_check_digit(digits, [5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2])
  second_digit = cnpj_check_digit(digits + [first_digit], [6, 5, 4, 3, 2, 9, 8, 7, 6, 5, 4, 3, 2])
  (digits + [first_digit, second_digit]).join
end

def seed_phone(area_code, key)
  "#{area_code}9#{seed_digits("phone-#{key}", 8)}"
end

ActiveRecord::Base.transaction do
  reset_seed_data!

  clinic = upsert_by(
    Organization,
    { cnpj: seed_cnpj("clinic") },
    {
      kind: "clinica",
      legal_name: "PrescSign Clinica Medica LTDA",
      trade_name: "PrescSign Clinica",
      name: "PrescSign Clinica",
      email: "contato@prescsign.test",
      phone: seed_phone("11", "clinic"),
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

  second_clinic = upsert_by(
    Organization,
    { cnpj: seed_cnpj("second-clinic") },
    {
      kind: "clinica",
      legal_name: "PrescSign Clinica Zona Sul LTDA",
      trade_name: "PrescSign Zona Sul",
      name: "PrescSign Zona Sul",
      email: "contato.zonasul@prescsign.test",
      phone: seed_phone("11", "second-clinic"),
      zip_code: "04552000",
      street: "Avenida Santo Amaro",
      number: "2200",
      complement: "Sala 804",
      district: "Itaim Bibi",
      city: "Sao Paulo",
      state: "SP",
      country: "BR",
      active: true,
      metadata: { seed: true, plan: "demo", secondary_clinic: true }
    }
  )

  hospital = upsert_by(
    Organization,
    { cnpj: seed_cnpj("hospital") },
    {
      kind: "hospital",
      legal_name: "Hospital Vida Digital SA",
      trade_name: "Hospital Vida Digital",
      name: "Hospital Vida Digital",
      email: "operacoes@hospitalvida.test",
      phone: seed_phone("21", "hospital"),
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

  second_clinic_default_unit = second_clinic.default_unit
  second_clinic_default_unit.update!(name: "Unidade Zona Sul", code: "ZONA-SUL", active: true)

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

  support = upsert_by(
    User,
    { email: "support@prescsign.test" },
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

  hospital_responsible = upsert_by(
    User,
    { email: "hospital@prescsign.test" },
    {
      password: SEED_PASSWORD,
      password_confirmation: SEED_PASSWORD,
      status: "active",
      confirmed_at: SEED_NOW,
      current_organization: hospital
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

  sync_user_roles(admin, %w[admin])
  sync_user_roles(support, %w[support])
  sync_user_roles(doctor, %w[doctor])
  sync_user_roles(staff, %w[manager])
  sync_user_roles(hospital_responsible, %w[manager])
  sync_user_roles(hospital_doctor, %w[doctor])

  [
    [admin, clinic, "owner"],
    [support, clinic, "staff"],
    [support, second_clinic, "staff"],
    [support, hospital, "staff"],
    [doctor, clinic, "doctor"],
    [doctor, second_clinic, "doctor"],
    [staff, clinic, "admin"],
    [hospital_responsible, hospital, "admin"],
    [hospital_doctor, hospital, "doctor"]
  ].each do |user, organization, role|
    upsert_by(
      OrganizationMembership,
      { user: user, organization: organization },
      { role: role, status: "active" }
    )
  end

  OrganizationResponsible.where(organization: clinic, user: admin).delete_all
  OrganizationResponsible.where(organization: hospital, user: hospital_doctor).delete_all

  upsert_by(OrganizationResponsible, { organization: clinic, user: staff }, {})
  upsert_by(OrganizationResponsible, { organization: hospital, user: hospital_responsible }, {})

  upsert_by(
    DoctorProfile,
    { user: doctor },
    {
      full_name: "Dra. Ana Beatriz Costa",
      cpf: seed_cpf("doctor-ana"),
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
      cpf: seed_cpf("doctor-rafael"),
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
      key: { organization: clinic, cpf: seed_cpf("patient-mariana") },
      attrs: {
        user: doctor,
        full_name: "Mariana Almeida",
        birth_date: Date.new(1988, 4, 15),
        email: "mariana.almeida@example.test",
        phone: seed_phone("11", "patient-mariana"),
        active: true
      }
    },
    {
      key: { organization: clinic, cpf: seed_cpf("patient-carlos") },
      attrs: {
        user: doctor,
        full_name: "Carlos Henrique Souza",
        birth_date: Date.new(1976, 9, 3),
        email: "carlos.souza@example.test",
        phone: seed_phone("11", "patient-carlos"),
        active: true
      }
    },
    {
      key: { organization: hospital, cpf: seed_cpf("patient-luciana") },
      attrs: {
        user: hospital_doctor,
        full_name: "Luciana Ferreira",
        birth_date: Date.new(1992, 12, 20),
        email: "luciana.ferreira@example.test",
        phone: seed_phone("21", "patient-luciana"),
        active: true
      }
    },
    {
      key: { organization: clinic, cpf: seed_cpf("patient-fernanda") },
      attrs: {
        user: doctor,
        full_name: "Fernanda Lima Rocha",
        birth_date: Date.new(1995, 7, 8),
        email: "fernanda.rocha@example.test",
        phone: seed_phone("11", "patient-fernanda"),
        active: true
      }
    },
    {
      key: { organization: hospital, cpf: seed_cpf("patient-roberto") },
      attrs: {
        user: hospital_doctor,
        full_name: "Roberto Azevedo",
        birth_date: Date.new(1968, 2, 27),
        email: "roberto.azevedo@example.test",
        phone: seed_phone("21", "patient-roberto"),
        active: true
      }
    },
    {
      key: { organization: clinic, cpf: seed_cpf("patient-julia") },
      attrs: {
        user: doctor,
        full_name: "Julia Nascimento",
        birth_date: Date.new(2001, 11, 4),
        email: "julia.nascimento@example.test",
        phone: seed_phone("11", "patient-julia"),
        active: false
      }
    },
    {
      key: { organization: second_clinic, cpf: seed_cpf("patient-patricia") },
      attrs: {
        user: doctor,
        full_name: "Patricia Campos",
        birth_date: Date.new(1983, 6, 12),
        email: "patricia.campos@example.test",
        phone: seed_phone("11", "patient-patricia"),
        active: true
      }
    },
    {
      key: { organization: second_clinic, cpf: seed_cpf("patient-eduardo") },
      attrs: {
        user: doctor,
        full_name: "Eduardo Moreira",
        birth_date: Date.new(1979, 10, 30),
        email: "eduardo.moreira@example.test",
        phone: seed_phone("11", "patient-eduardo"),
        active: true
      }
    }
  ].map { |entry| upsert_by(Patient, entry.fetch(:key), entry.fetch(:attrs)) }

  mariana, carlos, luciana, fernanda, roberto, julia, patricia, eduardo = patients

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
    },
    {
      key: { patient: fernanda, user: doctor, scheduled_at: SEED_NOW + 4.hours },
      attrs: {
        organization: clinic,
        status: "scheduled",
        chief_complaint: "Renovacao de receita",
        notes: "Paciente trouxe exames recentes.",
        metadata: { source: "seed", room: "202" }
      }
    },
    {
      key: { patient: roberto, user: hospital_doctor, scheduled_at: SEED_NOW - 1.day },
      attrs: {
        organization: hospital,
        status: "completed",
        finished_at: SEED_NOW - 1.day + 50.minutes,
        chief_complaint: "Dor toracica atipica",
        diagnosis: "Dor toracica inespecifica",
        notes: "Eletrocardiograma sem alteracoes agudas.",
        metadata: { source: "seed", priority: "high" }
      }
    },
    {
      key: { patient: julia, user: doctor, scheduled_at: SEED_NOW - 3.days },
      attrs: {
        organization: clinic,
        status: "cancelled",
        chief_complaint: "Consulta de rotina",
        notes: "Cancelada pela paciente.",
        metadata: { source: "seed", cancellation_reason: "patient_request" }
      }
    },
    {
      key: { patient: patricia, user: doctor, scheduled_at: SEED_NOW + 3.days },
      attrs: {
        organization: second_clinic,
        status: "scheduled",
        chief_complaint: "Acompanhamento de hipertensao",
        notes: "Consulta na segunda clinica do mesmo medico.",
        metadata: { source: "seed", room: "ZS-01" }
      }
    },
    {
      key: { patient: eduardo, user: doctor, scheduled_at: SEED_NOW - 4.days },
      attrs: {
        organization: second_clinic,
        status: "completed",
        finished_at: SEED_NOW - 4.days + 30.minutes,
        chief_complaint: "Rinite alergica",
        diagnosis: "Rinite alergica sazonal",
        notes: "Orientado controle ambiental e retorno se persistir.",
        metadata: { source: "seed", room: "ZS-02" }
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
puts "  admin@prescsign.test / #{SEED_PASSWORD} (admin)"
puts "  support@prescsign.test / #{SEED_PASSWORD} (support)"
puts "  medico@prescsign.test / #{SEED_PASSWORD} (medico em duas clinicas)"
puts "  recepcao@prescsign.test / #{SEED_PASSWORD} (responsavel pela clinica)"
puts "  hospital@prescsign.test / #{SEED_PASSWORD} (responsavel pelo hospital)"
puts "  hospital.medico@prescsign.test / #{SEED_PASSWORD} (medico do hospital)"
