# frozen_string_literal: true

def seed_delivery_logs!(context)
  clinic = context.fetch(:clinic)
  doctor = context.fetch(:doctor)
  sent_document = context.fetch(:sent_document)
  viewed_document = context.fetch(:viewed_document)

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
end
