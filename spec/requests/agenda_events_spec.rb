require "rails_helper"
require "securerandom"

RSpec.describe "Agenda events", type: :request do
  it "lists only the current doctor's consultations for regular doctors" do
    context = create_authenticated_context(role: "doctor")
    organization = context.fetch(:organization)
    doctor = context.fetch(:user)
    other_doctor = create_user(organization: organization)
    create_membership(user: other_doctor, organization: organization, role: "doctor")
    patient = context.fetch(:patient)
    other_patient = create_patient(user: other_doctor, organization: organization)

    visible = create_consultation(
      patient: patient,
      user: doctor,
      organization: organization,
      scheduled_at: Time.zone.parse("2026-05-06 09:00:00"),
      status: "scheduled"
    )
    hidden = create_consultation(
      patient: other_patient,
      user: other_doctor,
      organization: organization,
      scheduled_at: Time.zone.parse("2026-05-06 10:00:00"),
      status: "scheduled"
    )

    get "/v1/agenda/events",
        params: { starts_at: "2026-05-06T00:00:00Z", ends_at: "2026-05-07T00:00:00Z" },
        headers: auth_headers(context.fetch(:access_token))

    expect(response).to have_http_status(:ok)
    ids = JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }
    expect(ids).to include(visible.id)
    expect(ids).not_to include(hidden.id)
  end

  it "lists organization consultations for clinic admins" do
    context = create_authenticated_context(role: "admin")
    organization = context.fetch(:organization)
    admin = context.fetch(:user)
    doctor = create_user(organization: organization)
    create_membership(user: doctor, organization: organization, role: "doctor")
    patient = context.fetch(:patient)
    doctor_patient = create_patient(user: doctor, organization: organization)

    admin_consultation = create_consultation(
      patient: patient,
      user: admin,
      organization: organization,
      scheduled_at: Time.zone.parse("2026-05-06 09:00:00"),
      status: "scheduled"
    )
    doctor_consultation = create_consultation(
      patient: doctor_patient,
      user: doctor,
      organization: organization,
      scheduled_at: Time.zone.parse("2026-05-06 10:00:00"),
      status: "scheduled"
    )

    get "/v1/agenda/events",
        params: { starts_at: "2026-05-06T00:00:00Z", ends_at: "2026-05-07T00:00:00Z" },
        headers: auth_headers(context.fetch(:access_token))

    expect(response).to have_http_status(:ok)
    ids = JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }
    expect(ids).to include(admin_consultation.id, doctor_consultation.id)
  end

  it "filters organization agenda by doctor for clinic admins" do
    context = create_authenticated_context(role: "admin")
    organization = context.fetch(:organization)
    doctor = create_user(organization: organization)
    other_doctor = create_user(organization: organization)
    create_membership(user: doctor, organization: organization, role: "doctor")
    create_membership(user: other_doctor, organization: organization, role: "doctor")
    doctor_patient = create_patient(user: doctor, organization: organization)
    other_patient = create_patient(user: other_doctor, organization: organization)

    visible = create_consultation(
      patient: doctor_patient,
      user: doctor,
      organization: organization,
      scheduled_at: Time.zone.parse("2026-05-06 09:00:00"),
      status: "scheduled"
    )
    hidden = create_consultation(
      patient: other_patient,
      user: other_doctor,
      organization: organization,
      scheduled_at: Time.zone.parse("2026-05-06 10:00:00"),
      status: "scheduled"
    )

    get "/v1/agenda/events",
        params: {
          starts_at: "2026-05-06T00:00:00Z",
          ends_at: "2026-05-07T00:00:00Z",
          doctor_id: doctor.id
        },
        headers: auth_headers(context.fetch(:access_token))

    expect(response).to have_http_status(:ok)
    ids = JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }
    expect(ids).to include(visible.id)
    expect(ids).not_to include(hidden.id)
  end

  it "does not include consultations from another tenant" do
    context = create_authenticated_context(role: "admin")
    organization = context.fetch(:organization)
    patient = context.fetch(:patient)
    own_consultation = create_consultation(
      patient: patient,
      user: context.fetch(:user),
      organization: organization,
      scheduled_at: Time.zone.parse("2026-05-06 09:00:00"),
      status: "scheduled"
    )

    other_org = create_organization
    other_user = create_user(organization: other_org)
    create_membership(user: other_user, organization: other_org, role: "admin")
    other_patient = create_patient(user: other_user, organization: other_org)
    outside_consultation = create_consultation(
      patient: other_patient,
      user: other_user,
      organization: other_org,
      scheduled_at: Time.zone.parse("2026-05-06 10:00:00"),
      status: "scheduled"
    )

    get "/v1/agenda/events",
        params: { starts_at: "2026-05-06T00:00:00Z", ends_at: "2026-05-07T00:00:00Z" },
        headers: auth_headers(context.fetch(:access_token))

    expect(response).to have_http_status(:ok)
    ids = JSON.parse(response.body).fetch("data").map { |row| row.fetch("id") }
    expect(ids).to include(own_consultation.id)
    expect(ids).not_to include(outside_consultation.id)
  end

  it "returns event details expected by calendar clients" do
    context = create_authenticated_context(role: "doctor")
    consultation = context.fetch(:consultation)

    get "/v1/agenda/events",
        params: { starts_at: 1.hour.ago.iso8601, ends_at: 1.hour.from_now.iso8601 },
        headers: auth_headers(context.fetch(:access_token))

    expect(response).to have_http_status(:ok)
    event = JSON.parse(response.body).fetch("data").first
    expect(event).to include(
      "id" => consultation.id,
      "type" => "consultation",
      "title" => "Consulta - #{context.fetch(:patient).full_name}",
      "consultation_id" => consultation.id,
      "organization_id" => context.fetch(:organization).id,
      "doctor_id" => context.fetch(:user).id,
      "patient_id" => context.fetch(:patient).id,
      "patient_name" => context.fetch(:patient).full_name,
      "status" => "scheduled"
    )
    expect(event.fetch("starts_at")).to be_present
    expect(event.fetch("ends_at")).to be_present
  end

  private

  def auth_headers(token)
    { "HOST" => "localhost", "Authorization" => "Bearer #{token}" }
  end

  def create_authenticated_context(role:)
    organization = create_organization
    user = create_user(organization: organization)
    create_membership(user: user, organization: organization, role: role)
    patient = create_patient(user: user, organization: organization)
    consultation = create_consultation(
      patient: patient,
      user: user,
      organization: organization,
      scheduled_at: Time.current,
      status: "scheduled"
    )
    access_token, = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)

    {
      organization: organization,
      user: user,
      patient: patient,
      consultation: consultation,
      access_token: access_token
    }
  end

  def create_organization
    suffix = SecureRandom.hex(4)
    Organization.create!(name: "Org Agenda #{suffix}", kind: "clinica")
  end

  def create_user(organization:)
    suffix = SecureRandom.hex(4)
    User.create!(
      email: "agenda.#{suffix}@example.com",
      encrypted_password: "encrypted-token",
      status: "active",
      current_organization: organization,
      confirmed_at: Time.current
    )
  end

  def create_membership(user:, organization:, role:)
    OrganizationMembership.create!(
      user: user,
      organization: organization,
      role: role,
      status: "active"
    )
  end

  def create_patient(user:, organization:)
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    Patient.create!(
      user: user,
      organization: organization,
      full_name: "Paciente Agenda #{suffix}",
      cpf: "54321#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1),
      active: true
    )
  end

  def create_consultation(patient:, user:, organization:, scheduled_at:, status:)
    Consultation.create!(
      patient: patient,
      user: user,
      organization: organization,
      scheduled_at: scheduled_at,
      status: status
    )
  end
end
