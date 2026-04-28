require "rails_helper"
require "securerandom"

RSpec.describe "Consultations authentication", type: :request do
  it "allows authenticated access to consultation endpoints" do
    context = create_authenticated_context
    access_token = context.fetch(:access_token)
    patient = context.fetch(:patient)
    consultation = context.fetch(:consultation)

    get "/v1/patients/#{patient.id}/consultations", headers: auth_headers(access_token)
    expect(response).to have_http_status(:ok)

    post "/v1/patients/#{patient.id}/consultations",
         params: { consultation: { scheduled_at: 1.day.from_now.iso8601, status: "scheduled" } },
         headers: auth_headers(access_token),
         as: :json
    expect(response).to have_http_status(:created)

    get "/v1/consultations/#{consultation.id}", headers: auth_headers(access_token)
    expect(response).to have_http_status(:ok)

    patch "/v1/consultations/#{consultation.id}",
          params: { consultation: { notes: "Atualizado via spec" } },
          headers: auth_headers(access_token),
          as: :json
    expect(response).to have_http_status(:ok)

    post "/v1/consultations/#{consultation.id}/cancel", headers: auth_headers(access_token), as: :json
    expect(response).to have_http_status(:ok)
  end

  it "returns unauthorized without token" do
    context = create_authenticated_context
    patient = context.fetch(:patient)
    consultation = context.fetch(:consultation)

    get "/v1/patients/#{patient.id}/consultations", headers: host_headers
    expect(response).to have_http_status(:unauthorized)

    post "/v1/patients/#{patient.id}/consultations", headers: host_headers, as: :json
    expect(response).to have_http_status(:unauthorized)

    get "/v1/consultations/#{consultation.id}", headers: host_headers
    expect(response).to have_http_status(:unauthorized)

    patch "/v1/consultations/#{consultation.id}", headers: host_headers, as: :json
    expect(response).to have_http_status(:unauthorized)

    post "/v1/consultations/#{consultation.id}/cancel", headers: host_headers, as: :json
    expect(response).to have_http_status(:unauthorized)
  end

  private

  def auth_headers(token)
    host_headers.merge("Authorization" => "Bearer #{token}")
  end

  def host_headers
    { "HOST" => "localhost" }
  end

  def create_authenticated_context
    organization = create_organization
    user = create_user(organization: organization)
    create_membership(user: user, organization: organization)
    patient = create_patient(user: user, organization: organization)
    consultation = Consultation.create!(
      patient: patient,
      user: user,
      organization: organization,
      scheduled_at: Time.current,
      status: "scheduled"
    )
    access_token, = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)

    { user: user, patient: patient, consultation: consultation, access_token: access_token }
  end

  def create_organization
    suffix = SecureRandom.hex(4)
    Organization.create!(
      name: "Org Consultas Auth #{suffix}",
      kind: "autonomo"
    )
  end

  def create_user(organization:)
    suffix = SecureRandom.hex(4)
    User.create!(
      email: "consultas.auth.#{suffix}@example.com",
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
      full_name: "Paciente Consultas Auth #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1),
      active: true
    )
  end
end
