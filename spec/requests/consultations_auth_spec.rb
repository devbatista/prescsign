require "rails_helper"
require "securerandom"

RSpec.describe "Consultations authentication", type: :request do
  it "allows authenticated access to consultation endpoints" do
    doctor = create_confirmed_doctor
    access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor.user, :user, nil)
    patient = create_patient(doctor: doctor)

    get "/v1/patients/#{patient.id}/consultations", headers: auth_headers(access_token)
    expect(response).to have_http_status(:not_implemented)

    post "/v1/patients/#{patient.id}/consultations", headers: auth_headers(access_token), as: :json
    expect(response).to have_http_status(:not_implemented)

    get "/v1/consultations/consultation-1", headers: auth_headers(access_token)
    expect(response).to have_http_status(:not_implemented)

    patch "/v1/consultations/consultation-1", headers: auth_headers(access_token), as: :json
    expect(response).to have_http_status(:not_implemented)

    post "/v1/consultations/consultation-1/cancel", headers: auth_headers(access_token), as: :json
    expect(response).to have_http_status(:not_implemented)
  end

  it "returns unauthorized without token" do
    doctor = create_confirmed_doctor
    patient = create_patient(doctor: doctor)

    get "/v1/patients/#{patient.id}/consultations", headers: host_headers
    expect(response).to have_http_status(:unauthorized)

    post "/v1/patients/#{patient.id}/consultations", headers: host_headers, as: :json
    expect(response).to have_http_status(:unauthorized)

    get "/v1/consultations/consultation-1", headers: host_headers
    expect(response).to have_http_status(:unauthorized)

    patch "/v1/consultations/consultation-1", headers: host_headers, as: :json
    expect(response).to have_http_status(:unauthorized)

    post "/v1/consultations/consultation-1/cancel", headers: host_headers, as: :json
    expect(response).to have_http_status(:unauthorized)
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
      full_name: "Dra Consultas Auth #{suffix}",
      email: "consultas.auth.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end

  def create_patient(doctor:)
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    Patient.create!(
      doctor: doctor,
      full_name: "Paciente Consultas Auth #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1),
      active: true
    )
  end
end
