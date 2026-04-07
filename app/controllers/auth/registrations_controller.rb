module Auth
  class RegistrationsController < ApplicationController
    def create
      doctor = Doctor.new(registration_params)
      return render_unprocessable(doctor) unless doctor.save

      access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)
      refresh_token = RefreshTokenService.issue_for(doctor)
      render json: {
        access_token: access_token,
        refresh_token: refresh_token,
        doctor: doctor_payload(doctor)
      }, status: :created
    end

    private

    def registration_params
      params.require(:doctor).permit(
        :full_name,
        :email,
        :cpf,
        :license_number,
        :license_state,
        :specialty,
        :password,
        :password_confirmation
      )
    end

    def doctor_payload(doctor)
      doctor.slice(
        :id,
        :full_name,
        :email,
        :cpf,
        :license_number,
        :license_state,
        :specialty,
        :active,
        :created_at,
        :updated_at
      )
    end

    def render_unprocessable(doctor)
      render json: { errors: doctor.errors.full_messages }, status: :unprocessable_entity
    end
  end
end
