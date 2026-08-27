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
      # Nomes de provedor como os adapters registram de fato: o e-mail sai pelo
      # ActionMailer fora de produção (Deliveries::Adapters::EmailAdapter) e o
      # WhatsApp pelo Twilio.
      provider_name: "action_mailer",
      provider_message_id: "seed-msg-0001@prescsign.test",
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
      provider_name: "twilio",
      recipient: viewed_document.patient.phone,
      # Falha típica do canal no Sandbox do Twilio: fora da janela de 24 horas
      # aberta pela última mensagem do paciente, o provedor recusa o envio.
      error_code: "63016",
      error_message: "Twilio recusou a mensagem: janela de 24h do WhatsApp expirada",
      attempted_at: SEED_NOW + 10.minutes,
      request_id: "seed-request-whatsapp-0001",
      metadata: { seed: true, retryable: true }
    }
  )
end
