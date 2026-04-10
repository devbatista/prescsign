require "rails_helper"
require "securerandom"

RSpec.describe "Patients", type: :request do
  describe "POST /v1/patients" do
    it "creates a patient linked to current doctor" do
      doctor = create_confirmed_doctor
      access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)

      post "/v1/patients", params: {
        patient: {
          full_name: "Paciente Teste",
          cpf: "123.456.789-01",
          birth_date: "1990-01-01",
          email: "paciente@example.com",
          phone: "(11) 99999-0000"
        }
      }, headers: auth_headers(access_token), as: :json

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["doctor_id"]).to eq(doctor.id)
      expect(body["cpf"]).to eq("12345678901")
    end
  end

  describe "GET /v1/patients" do
    it "returns only owned patients with pagination metadata" do
      doctor = create_confirmed_doctor
      other_doctor = create_confirmed_doctor
      own_patient = create_patient(doctor: doctor, full_name: "Ana Clara", cpf: "11111111111")
      _other_patient = create_patient(doctor: other_doctor, full_name: "Bruno Lima", cpf: "22222222222")
      access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)

      get "/v1/patients", params: { page: 1, per_page: 10 }, headers: auth_headers(access_token)

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      ids = body.fetch("data").map { |patient| patient["id"] }
      expect(ids).to include(own_patient.id)
      expect(body.fetch("meta")["page"]).to eq(1)
      expect(body.fetch("meta")["per_page"]).to eq(10)
    end

    it "supports search by name and cpf" do
      doctor = create_confirmed_doctor
      create_patient(doctor: doctor, full_name: "Paciente Nome Alvo", cpf: "33333333333")
      create_patient(doctor: doctor, full_name: "Outro Paciente", cpf: "44444444444")
      access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)

      get "/v1/patients", params: { q: "Nome Alvo" }, headers: auth_headers(access_token)
      by_name = JSON.parse(response.body).fetch("data")
      expect(by_name.size).to eq(1)

      get "/v1/patients", params: { q: "333.333.333-33" }, headers: auth_headers(access_token)
      by_cpf = JSON.parse(response.body).fetch("data")
      expect(by_cpf.size).to eq(1)
    end
  end

  describe "GET /v1/patients/:id" do
    it "returns an owned patient" do
      doctor = create_confirmed_doctor
      patient = create_patient(doctor: doctor, full_name: "Paciente Show", cpf: "55555555555")
      access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)

      get "/v1/patients/#{patient.id}", headers: auth_headers(access_token)

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["id"]).to eq(patient.id)
    end
  end

  describe "PATCH /v1/patients/:id" do
    it "updates an owned patient" do
      doctor = create_confirmed_doctor
      patient = create_patient(doctor: doctor, full_name: "Paciente Antigo", cpf: "66666666666")
      access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)

      patch "/v1/patients/#{patient.id}", params: {
        patient: { full_name: "Paciente Novo", phone: "11988887777" }
      }, headers: auth_headers(access_token), as: :json

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["full_name"]).to eq("Paciente Novo")
      expect(body["phone"]).to eq("11988887777")
    end
  end

  describe "DELETE /v1/patients/:id" do
    it "inactivates an owned patient" do
      doctor = create_confirmed_doctor
      patient = create_patient(doctor: doctor, full_name: "Paciente Ativo", cpf: "77777777777")
      access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)

      delete "/v1/patients/#{patient.id}", headers: auth_headers(access_token), as: :json

      expect(response).to have_http_status(:no_content)
      expect(patient.reload.active).to be(false)
    end
  end

  private

  def auth_headers(token)
    host_headers.merge("Authorization" => "Bearer #{token}")
  end

  def host_headers
    { "HOST" => "localhost" }
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dra Pacientes #{suffix}",
      email: "pacientes.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end

  def create_patient(doctor:, full_name:, cpf:)
    Patient.create!(
      doctor: doctor,
      full_name: full_name,
      cpf: cpf,
      birth_date: Date.new(1990, 1, 1),
      active: true
    )
  end
end
