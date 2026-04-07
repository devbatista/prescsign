module V1
  module Auth
    class RegistrationsController < ApplicationController
      def create
        doctor = Doctor.new(registration_params)
        return render_unprocessable(doctor) unless doctor.valid?

        access_token = nil
        refresh_token = nil

        ActiveRecord::Base.transaction do
          doctor.save!
          access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)
          refresh_token = ::Auth::RefreshTokenService.issue_for(doctor)
        end

        render json: {
          access_token: access_token,
          refresh_token: refresh_token,
          doctor: doctor_payload(doctor)
        }, status: :created
      rescue ActiveRecord::RecordInvalid
        render json: { error: "Could not complete registration" }, status: :unprocessable_entity
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
end
