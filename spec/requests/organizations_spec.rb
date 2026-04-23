require "rails_helper"
require "securerandom"

RSpec.describe "Organizations", type: :request do
  it "creates organization without explicit name using trade/legal name and provisions responsible account" do
    doctor = create_confirmed_doctor
    access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor.user, :user, nil)
    suffix = SecureRandom.hex(4)
    responsible_email = "responsavel.#{suffix}@example.com"

    post "/v1/organizations",
         params: {
           organization: {
             kind: "clinica",
             legal_name: "Clinica Bem Cuidar LTDA",
             trade_name: "Bem Cuidar",
             cnpj: unique_cnpj,
             responsible_email: responsible_email
           }
         },
         headers: auth_headers(access_token),
         as: :json

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)
    organization_id = body.dig("organization", "id")
    expect(body.dig("organization", "name")).to eq("Bem Cuidar")
    expect(body["responsible_email"]).to eq(responsible_email)
    expect(body.dig("organization", "units")).not_to be_empty

    organization = Organization.find(organization_id)
    expect(organization.name).to eq("Bem Cuidar")

    responsible_user = User.find_by(email: responsible_email)
    expect(responsible_user).to be_present
    expect(OrganizationResponsible.where(organization: organization, user: responsible_user)).to exist
    expect(responsible_user.organization_memberships.find_by(organization: organization)&.role).to eq("admin")
    expect(doctor.user.organization_memberships.find_by(organization: organization)&.role).to eq("owner")
  end

  it "returns unprocessable content when responsible_email is missing on create" do
    doctor = create_confirmed_doctor
    access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor.user, :user, nil)

    post "/v1/organizations",
         params: {
           organization: {
             kind: "clinica",
             legal_name: "Clinica Sem Responsavel LTDA",
             cnpj: unique_cnpj
           }
         },
         headers: auth_headers(access_token),
         as: :json

    expect(response).to have_http_status(:unprocessable_content)
    body = JSON.parse(response.body)
    expect(body["error"]).to eq("Responsible email is required")
  end

  it "links an existing confirmed responsible user to the new organization" do
    doctor = create_confirmed_doctor
    access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor.user, :user, nil)
    suffix = SecureRandom.hex(4)
    responsible_user = create_confirmed_doctor_user(
      email: "responsavel.confirmado.#{suffix}@example.com"
    )

    post "/v1/organizations",
         params: {
           organization: {
             kind: "clinica",
             legal_name: "Clinica Fluxo Reset LTDA",
             cnpj: unique_cnpj,
             responsible_email: responsible_user.email
           }
         },
         headers: auth_headers(access_token),
         as: :json

    expect(response).to have_http_status(:created)
    organization_id = JSON.parse(response.body).dig("organization", "id")
    membership = responsible_user.organization_memberships.find_by(organization_id: organization_id)
    expect(membership).to be_present
    expect(membership.role).to eq("admin")
  end

  it "lists active organizations for current doctor" do
    doctor = create_confirmed_doctor
    access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor.user, :user, nil)

    get "/v1/organizations", headers: auth_headers(access_token)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["current_organization_id"]).to eq(doctor.reload.current_organization_id)
    expect(body.fetch("organizations")).not_to be_empty
    expect(body.dig("meta", "page")).to eq(1)
    expect(body.dig("meta", "per_page")).to eq(20)
    expect(body.dig("meta", "sort_by")).to eq("created_at")
    expect(body.dig("meta", "sort_dir")).to eq("asc")
  end

  it "switches active organization when doctor belongs to target organization" do
    doctor = create_confirmed_doctor
    second_organization = Organization.create!(
      name: "Clinica Alfa",
      kind: "clinica",
      legal_name: "Clinica Alfa LTDA",
      cnpj: unique_cnpj,
      active: true
    )
    OrganizationMembership.create!(doctor: doctor, organization: second_organization, role: "doctor", status: "active")
    access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor.user, :user, nil)

    post "/v1/organizations/#{second_organization.id}/switch", headers: auth_headers(access_token), as: :json

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    expect(body["current_organization_id"]).to eq(second_organization.id)
    expect(doctor.reload.current_organization_id).to eq(second_organization.id)
  end

  it "isolates patient access by active organization context" do
    doctor = create_confirmed_doctor
    primary_organization = doctor.current_organization
    secondary_organization = Organization.create!(
      name: "Hospital Beta",
      kind: "hospital",
      legal_name: "Hospital Beta SA",
      cnpj: unique_cnpj,
      active: true
    )
    OrganizationMembership.create!(doctor: doctor, organization: secondary_organization, role: "doctor", status: "active")

    patient_in_secondary = Patient.create!(
      doctor: doctor,
      organization: secondary_organization,
      full_name: "Paciente Tenant",
      cpf: unique_cpf,
      birth_date: Date.new(1991, 2, 3)
    )

    access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor.user, :user, nil)

    get "/v1/patients/#{patient_in_secondary.id}", headers: auth_headers(access_token)
    expect(response).to have_http_status(:not_found)

    get "/v1/patients/#{patient_in_secondary.id}", headers: auth_headers(access_token, organization_id: secondary_organization.id)
    expect(response).to have_http_status(:ok)

    get "/v1/patients", headers: auth_headers(access_token, organization_id: primary_organization.id)
    expect(response).to have_http_status(:ok)
  end

  it "does not list or switch to inactive organizations" do
    doctor = create_confirmed_doctor
    inactive_organization = Organization.create!(
      name: "Unidade Inativa",
      kind: "autonomo",
      active: false
    )
    OrganizationMembership.create!(doctor: doctor, organization: inactive_organization, role: "doctor", status: "active")
    access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor.user, :user, nil)

    get "/v1/organizations", headers: auth_headers(access_token)

    expect(response).to have_http_status(:ok)
    body = JSON.parse(response.body)
    listed_ids = body.fetch("organizations").map { |organization| organization.fetch("id") }
    expect(listed_ids).not_to include(inactive_organization.id)

    post "/v1/organizations/#{inactive_organization.id}/switch", headers: auth_headers(access_token), as: :json
    expect(response).to have_http_status(:not_found)
  end

  it "avoids N+1 queries when loading organization units list" do
    doctor = create_confirmed_doctor

    3.times do |idx|
      organization = Organization.create!(
        name: "Clinica #{idx}",
        kind: "clinica",
        legal_name: "Clinica #{idx} LTDA",
        cnpj: unique_cnpj,
        active: true
      )
      OrganizationMembership.create!(doctor: doctor, organization: organization, role: "doctor", status: "active")
      organization.units.create!(name: "Filial #{idx}", code: "U#{idx}")
    end

    access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor.user, :user, nil)
    sql = []
    subscriber = lambda do |_name, _start, _finish, _id, payload|
      next if payload[:name].in?(%w[SCHEMA CACHE])
      next unless payload[:sql].to_s.include?("FROM \"units\"")

      sql << payload[:sql]
    end

    ActiveSupport::Notifications.subscribed(subscriber, "sql.active_record") do
      get "/v1/organizations", headers: auth_headers(access_token)
    end

    expect(response).to have_http_status(:ok)
    expect(sql.count { |query| query.strip.start_with?("SELECT") }).to be <= 1
  end

  private

  def auth_headers(token, organization_id: nil)
    headers = host_headers.merge("Authorization" => "Bearer #{token}")
    headers["X-Organization-Id"] = organization_id.to_s if organization_id.present?
    headers
  end

  def host_headers
    { "HOST" => "localhost" }
  end

  def unique_cpf
    SecureRandom.random_number(10**11).to_s.rjust(11, "0")
  end

  def unique_cnpj
    SecureRandom.random_number(10**14).to_s.rjust(14, "0")
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dra Organizacao #{suffix}",
      email: "organizacao.#{suffix}@example.com",
      cpf: "92345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end

  def create_confirmed_doctor_user(email:)
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dra Conta Existente #{suffix}",
      email: email,
      cpf: "89345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.user
  end
end
