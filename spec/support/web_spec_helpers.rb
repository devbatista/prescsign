require "securerandom"

# Helpers for the server-rendered web layer (App:: controllers on subdomains).
# Session auth via Devise; hosts are unrestricted in test (config.hosts empty).
module WebSpecHelpers
  APP_HOST      = "app.prescsign.local".freeze
  LOGIN_HOST    = "login.prescsign.local".freeze
  REGISTER_HOST = "register.prescsign.local".freeze

  def use_app_host!    = host!(APP_HOST)
  def use_login_host!  = host!(LOGIN_HOST)

  def sign_in_web(user)
    sign_in(user, scope: :user)
  end

  def create_organization(kind: "clinica")
    suffix = SecureRandom.hex(4)
    Organization.create!(
      name: "Org #{suffix}",
      legal_name: "Org #{suffix} LTDA",
      cnpj: SecureRandom.random_number(10**14).to_s.rjust(14, "0"),
      kind: kind
    )
  end

  def create_user(organization:, password: "password123", email: nil)
    User.create!(
      email: email || "user.#{SecureRandom.hex(4)}@example.com",
      password: password,
      password_confirmation: password,
      status: "active",
      current_organization: organization,
      confirmed_at: Time.current
    )
  end

  def grant_role(user, role)
    UserRole.create!(user: user, role: role, status: "active")
  end

  def create_membership(user:, organization:, role:)
    OrganizationMembership.create!(user: user, organization: organization, role: role, status: "active")
  end

  def create_doctor_profile(user:)
    DoctorProfile.create!(
      user: user,
      full_name: "Dr #{SecureRandom.hex(3)}",
      email: user.email,
      license_number: "CRM#{SecureRandom.hex(3).upcase}",
      license_state: "SP",
      active: true
    )
  end

  def create_patient(user:, organization:, active: true)
    Patient.create!(
      user: user,
      organization: organization,
      full_name: "Paciente #{SecureRandom.hex(4)}",
      cpf: "9#{SecureRandom.random_number(10**10).to_s.rjust(10, '0')}",
      birth_date: Date.new(1990, 1, 1),
      active: active
    )
  end

  def create_specialty(name: "Cardiologia")
    Specialty.find_or_create_by_name!(name)
  end

  def assign_specialty(doctor:, specialty: create_specialty)
    doctor.doctor_profile.doctor_specialties.create!(specialty: specialty)
  end

  # Personas -----------------------------------------------------------------

  def create_org_responsible(organization:)
    user = create_user(organization: organization)
    create_membership(user: user, organization: organization, role: "owner")
    user
  end

  def create_doctor(organization:)
    user = create_user(organization: organization)
    create_membership(user: user, organization: organization, role: "doctor")
    grant_role(user, "doctor")
    create_doctor_profile(user: user)
    user
  end

  def create_admin(organization:)
    user = create_user(organization: organization)
    create_membership(user: user, organization: organization, role: "owner")
    grant_role(user, "admin")
    user
  end

  # Builds a draft prescription with its Document + initial version, as the
  # controller does, so document actions (sign/revoke) can be exercised.
  def create_prescription_document(user:, patient:, organization:, content: "Conteúdo clínico de teste")
    prescription = user.prescriptions.create!(
      patient: patient, organization: organization,
      code: SecureRandom.alphanumeric(10).upcase, status: "draft",
      content: content, issued_on: Date.current
    )
    Documents::LifecycleService.new(actor: user).create_with_initial_version!(
      user: user, patient: patient, documentable: prescription,
      unit: organization.default_unit, kind: "prescription",
      issued_on: prescription.issued_on, content: prescription.content
    )
    prescription.reload
  end
end

RSpec.configure do |config|
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.include WebSpecHelpers, type: :request
end
