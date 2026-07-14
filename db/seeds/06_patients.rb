# frozen_string_literal: true

def seed_patients!(context)
  clinic = context.fetch(:clinic)
  second_clinic = context.fetch(:second_clinic)
  hospital = context.fetch(:hospital)
  doctor = context.fetch(:doctor)
  hospital_doctor = context.fetch(:hospital_doctor)

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

  {
    patients: patients,
    mariana: mariana,
    carlos: carlos,
    luciana: luciana,
    fernanda: fernanda,
    roberto: roberto,
    julia: julia,
    patricia: patricia,
    eduardo: eduardo
  }
end
