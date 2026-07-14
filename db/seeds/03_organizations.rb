# frozen_string_literal: true

def seed_organizations!
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

  {
    clinic: clinic,
    second_clinic: second_clinic,
    hospital: hospital,
    clinic_default_unit: clinic_default_unit,
    clinic_lab_unit: clinic_lab_unit,
    second_clinic_default_unit: second_clinic_default_unit,
    hospital_default_unit: hospital_default_unit
  }
end
