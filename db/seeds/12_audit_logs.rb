# frozen_string_literal: true

def seed_audit_logs!(context)
  doctor = context.fetch(:doctor)
  prescription = context.fetch(:prescription)
  certificate = context.fetch(:certificate)
  consultations = context.fetch(:consultations)

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
