# frozen_string_literal: true

def seed_doctor_profiles!(context)
  doctor = context.fetch(:doctor)
  hospital_doctor = context.fetch(:hospital_doctor)
  demo_doctors = context.fetch(:demo_doctors)
  specialties_by_name = context.fetch(:specialties_by_name)

  ana_profile = upsert_by(
    DoctorProfile,
    { user: doctor },
    {
      full_name: "Dra. Ana Beatriz Costa",
      cpf: seed_cpf("doctor-ana"),
      email: doctor.email,
      license_number: "CRM123456",
      license_state: "SP",
      gender: "female",
      active: true
    }
  )

  rafael_profile = upsert_by(
    DoctorProfile,
    { user: hospital_doctor },
    {
      full_name: "Dr. Rafael Martins",
      cpf: seed_cpf("doctor-rafael"),
      email: hospital_doctor.email,
      license_number: "CRM654321",
      license_state: "RJ",
      gender: "male",
      active: true
    }
  )

  clinica_medica = specialties_by_name.fetch("Clínica Médica")
  cardiologia = specialties_by_name.fetch("Cardiologia")
  upsert_by(DoctorSpecialty, { doctor_profile: ana_profile, specialty: clinica_medica }, { rqe_number: "RQE-11111" })
  upsert_by(DoctorSpecialty, { doctor_profile: rafael_profile, specialty: cardiologia }, { rqe_number: "RQE-22222" })

  demo_profile_specs = [
    {
      user: demo_doctors.first,
      full_name: "Dra. Laura Mendes",
      cpf_key: "doctor-laura",
      license_number: "CRM223344",
      license_state: "SP",
      gender: "female",
      specialty: "Dermatologia",
      rqe_number: "RQE-33333"
    },
    {
      user: demo_doctors.second,
      full_name: "Dr. Felipe Andrade",
      cpf_key: "doctor-felipe",
      license_number: "CRM334455",
      license_state: "SP",
      gender: "male",
      specialty: "Pediatria",
      rqe_number: "RQE-44444"
    },
    {
      user: demo_doctors.third,
      full_name: "Dr. Bruno Carvalho",
      cpf_key: "doctor-bruno",
      license_number: "CRM445566",
      license_state: "SP",
      gender: "male",
      specialty: "Ortopedia e Traumatologia",
      rqe_number: "RQE-55555"
    },
    {
      user: demo_doctors.fourth,
      full_name: "Dra. Camila Torres",
      cpf_key: "doctor-camila",
      license_number: "CRM556677",
      license_state: "SP",
      gender: "female",
      specialty: "Ginecologia e Obstetrícia",
      rqe_number: "RQE-66666"
    },
    {
      user: demo_doctors.fifth,
      full_name: "Dra. Renata Lopes",
      cpf_key: "doctor-renata",
      license_number: "CRM667788",
      license_state: "SP",
      gender: "female",
      specialty: "Psiquiatria",
      rqe_number: "RQE-77777"
    }
  ]

  demo_profiles = demo_profile_specs.map do |spec|
    profile = upsert_by(
      DoctorProfile,
      { user: spec.fetch(:user) },
      {
        full_name: spec.fetch(:full_name),
        cpf: seed_cpf(spec.fetch(:cpf_key)),
        email: spec.fetch(:user).email,
        license_number: spec.fetch(:license_number),
        license_state: spec.fetch(:license_state),
        gender: spec.fetch(:gender),
        active: true
      }
    )

    upsert_by(
      DoctorSpecialty,
      { doctor_profile: profile, specialty: specialties_by_name.fetch(spec.fetch(:specialty)) },
      { rqe_number: spec.fetch(:rqe_number) }
    )

    profile
  end

  {
    ana_profile: ana_profile,
    rafael_profile: rafael_profile,
    demo_profiles: demo_profiles
  }
end
