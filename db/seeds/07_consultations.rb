# frozen_string_literal: true

def seed_consultations!(context)
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
  clinica_medica = context.fetch(:specialties_by_name).fetch("Clínica Médica")
  cardiologia = context.fetch(:specialties_by_name).fetch("Cardiologia")

  consultations = [
    {
      key: { patient: mariana, user: doctor, scheduled_at: SEED_NOW + 1.day },
      attrs: {
        organization: clinic,
        specialty: clinica_medica,
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
        specialty: clinica_medica,
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
        specialty: cardiologia,
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
        specialty: clinica_medica,
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
        specialty: cardiologia,
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
        specialty: clinica_medica,
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
        specialty: clinica_medica,
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
        specialty: clinica_medica,
        status: "completed",
        finished_at: SEED_NOW - 4.days + 30.minutes,
        chief_complaint: "Rinite alergica",
        diagnosis: "Rinite alergica sazonal",
        notes: "Orientado controle ambiental e retorno se persistir.",
        metadata: { source: "seed", room: "ZS-02" }
      }
    }
  ].map { |entry| upsert_by(Consultation, entry.fetch(:key), entry.fetch(:attrs)) }

  { consultations: consultations }
end
