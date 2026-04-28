require "rails_helper"
require "securerandom"

RSpec.describe "Consultations", type: :request do
  it "lists patient consultations ordered by scheduled_at desc with pagination metadata" do
    context = create_authenticated_context
    token = context.fetch(:access_token)
    patient = context.fetch(:patient)

    older = create_consultation(patient: patient, user: context.fetch(:user), organization: context.fetch(:organization), scheduled_at: 3.days.ago, status: "scheduled")
    newer = create_consultation(patient: patient, user: context.fetch(:user), organization: context.fetch(:organization), scheduled_at: 1.day.ago, status: "completed")

    get "/v1/patients/#{patient.id}/consultations",
        params: { page: 1, per_page: 10 },
        headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body.dig("meta", "page")).to eq(1)
    expect(body.dig("meta", "per_page")).to eq(10)
    expect(body.dig("meta", "sort_by")).to eq("scheduled_at")
    expect(body.dig("meta", "sort_dir")).to eq("desc")

    ids = body.fetch("data").map { |row| row.fetch("id") }
    expect(ids.index(newer.id)).to be < ids.index(older.id)
  end

  it "filters consultations by status and period" do
    context = create_authenticated_context
    token = context.fetch(:access_token)
    patient = context.fetch(:patient)
    user = context.fetch(:user)
    organization = context.fetch(:organization)

    in_range = create_consultation(patient: patient, user: user, organization: organization, scheduled_at: Time.zone.parse("2026-04-20 10:00:00"), status: "scheduled")
    _out_status = create_consultation(patient: patient, user: user, organization: organization, scheduled_at: Time.zone.parse("2026-04-20 12:00:00"), status: "completed")
    _out_range = create_consultation(patient: patient, user: user, organization: organization, scheduled_at: Time.zone.parse("2026-04-25 10:00:00"), status: "scheduled")

    get "/v1/patients/#{patient.id}/consultations",
        params: {
          status: "scheduled",
          scheduled_from: "2026-04-19T00:00:00Z",
          scheduled_to: "2026-04-21T23:59:59Z"
        },
        headers: auth_headers(token)

    expect(response).to have_http_status(:ok)
    data = JSON.parse(response.body).fetch("data")
    expect(data.map { |row| row.fetch("id") }).to include(in_range.id)
    expect(data.size).to eq(1)
  end

  it "creates consultation for patient in current tenant" do
    context = create_authenticated_context
    token = context.fetch(:access_token)
    patient = context.fetch(:patient)

    post "/v1/patients/#{patient.id}/consultations",
         params: {
           consultation: {
             scheduled_at: 2.days.from_now.iso8601,
             status: "scheduled",
             chief_complaint: "Dor de cabeca"
           }
         },
         headers: auth_headers(token),
         as: :json

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body["patient_id"]).to eq(patient.id)
    expect(body["status"]).to eq("scheduled")
    expect(body["chief_complaint"]).to eq("Dor de cabeca")
  end

  it "ignores non-permitted parameter on create" do
    context = create_authenticated_context
    token = context.fetch(:access_token)
    patient = context.fetch(:patient)

    post "/v1/patients/#{patient.id}/consultations",
         params: {
           consultation: {
             scheduled_at: 2.days.from_now.iso8601,
             status: "scheduled",
             random_unpermitted_key: "ignored"
           }
         },
         headers: auth_headers(token),
         as: :json

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    expect(body).not_to have_key("random_unpermitted_key")
  end

  it "shows and updates a consultation from current tenant" do
    context = create_authenticated_context
    token = context.fetch(:access_token)
    consultation = context.fetch(:consultation)

    get "/v1/consultations/#{consultation.id}", headers: auth_headers(token)
    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["id"]).to eq(consultation.id)

    patch "/v1/consultations/#{consultation.id}",
          params: { consultation: { notes: "Evolucao registrada" } },
          headers: auth_headers(token),
          as: :json

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)["notes"]).to eq("Evolucao registrada")
  end

  it "does not allow changing organization_id, patient_id and user_id via update" do
    context = create_authenticated_context
    token = context.fetch(:access_token)
    consultation = context.fetch(:consultation)

    other_org = create_organization
    other_user = create_user(organization: other_org)
    create_membership(user: other_user, organization: other_org)
    other_patient = create_patient(user: other_user, organization: other_org)

    original_org_id = consultation.organization_id
    original_patient_id = consultation.patient_id
    original_user_id = consultation.user_id

    patch "/v1/consultations/#{consultation.id}",
          params: {
            consultation: {
              organization_id: other_org.id,
              patient_id: other_patient.id,
              user_id: other_user.id,
              notes: "Tentativa de update sensivel"
            }
          },
          headers: auth_headers(token),
          as: :json

    expect(response).to have_http_status(:ok)
    consultation.reload
    expect(consultation.organization_id).to eq(original_org_id)
    expect(consultation.patient_id).to eq(original_patient_id)
    expect(consultation.user_id).to eq(original_user_id)
    expect(consultation.notes).to eq("Tentativa de update sensivel")
  end

  it "returns validation error for invalid status transition" do
    context = create_authenticated_context
    token = context.fetch(:access_token)
    consultation = context.fetch(:consultation)
    consultation.update!(status: "completed")

    patch "/v1/consultations/#{consultation.id}",
          params: { consultation: { status: "scheduled" } },
          headers: auth_headers(token),
          as: :json

    expect(response).to have_http_status(:unprocessable_content)
    expect(JSON.parse(response.body).fetch("error")).to include("transition from completed to scheduled is not allowed")
  end

  it "returns not found for consultation outside current tenant scope" do
    context = create_authenticated_context
    token = context.fetch(:access_token)

    other_org = create_organization
    other_user = create_user(organization: other_org)
    create_membership(user: other_user, organization: other_org)
    other_patient = create_patient(user: other_user, organization: other_org)
    outsider_consultation = create_consultation(
      patient: other_patient,
      user: other_user,
      organization: other_org,
      scheduled_at: Time.current,
      status: "scheduled"
    )

    get "/v1/consultations/#{outsider_consultation.id}", headers: auth_headers(token)
    expect(response).to have_http_status(:not_found)
  end

  private

  def auth_headers(token)
    { "HOST" => "localhost", "Authorization" => "Bearer #{token}" }
  end

  def create_authenticated_context
    organization = create_organization
    user = create_user(organization: organization)
    create_membership(user: user, organization: organization)
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
    Organization.create!(name: "Org Consultas #{suffix}", kind: "autonomo")
  end

  def create_user(organization:)
    suffix = SecureRandom.hex(4)
    User.create!(
      email: "consultations.#{suffix}@example.com",
      encrypted_password: "encrypted-token",
      status: "active",
      current_organization: organization,
      confirmed_at: Time.current
    )
  end

  def create_membership(user:, organization:)
    OrganizationMembership.create!(
      user: user,
      organization: organization,
      role: "doctor",
      status: "active"
    )
  end

  def create_patient(user:, organization:)
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    Patient.create!(
      user: user,
      organization: organization,
      full_name: "Paciente Consultas #{suffix}",
      cpf: "12345#{cpf_suffix}",
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
