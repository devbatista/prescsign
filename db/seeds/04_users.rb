# frozen_string_literal: true

def seed_users!(context)
  clinic = context.fetch(:clinic)
  second_clinic = context.fetch(:second_clinic)
  hospital = context.fetch(:hospital)

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

  demo_doctors = [
    "dermato@prescsign.test",
    "pediatra@prescsign.test",
    "ortopedista@prescsign.test",
    "gineco@prescsign.test",
    "psiquiatra@prescsign.test"
  ].map do |email|
    upsert_by(
      User,
      { email: email },
      {
        password: SEED_PASSWORD,
        password_confirmation: SEED_PASSWORD,
        status: "active",
        confirmed_at: SEED_NOW,
        current_organization: clinic
      }
    )
  end

  sync_user_roles(admin, %w[admin])
  sync_user_roles(support, %w[support])
  sync_user_roles(doctor, %w[doctor])
  sync_user_roles(staff, %w[manager])
  sync_user_roles(hospital_responsible, %w[manager])
  sync_user_roles(hospital_doctor, %w[doctor])
  demo_doctors.each { |demo_doctor| sync_user_roles(demo_doctor, %w[doctor]) }

  memberships = [
    [admin, clinic, "owner"],
    [support, clinic, "staff"],
    [support, second_clinic, "staff"],
    [support, hospital, "staff"],
    [doctor, clinic, "doctor"],
    [doctor, second_clinic, "doctor"],
    [staff, clinic, "owner"],
    [hospital_responsible, hospital, "owner"],
    [hospital_doctor, hospital, "doctor"]
  ]
  memberships += demo_doctors.map { |demo_doctor| [demo_doctor, clinic, "doctor"] }

  memberships.each do |user, organization, role|
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

  {
    admin: admin,
    doctor: doctor,
    support: support,
    staff: staff,
    hospital_responsible: hospital_responsible,
    hospital_doctor: hospital_doctor,
    demo_doctors: demo_doctors
  }
end
