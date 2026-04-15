module V1
  module Auth
    class RegistrationsController < ApplicationController
      def create
        doctor = Doctor.new(registration_params)
        return render_unprocessable(doctor) unless doctor.valid?

        ActiveRecord::Base.transaction do
          doctor.skip_confirmation_notification!
          doctor.save!
          doctor.send_confirmation_instructions
        end

        render json: {
          message: "Registration successful. Please confirm your email.",
          doctor: doctor_payload(doctor)
        }, status: :created
      rescue StandardError => e
        Rails.logger.error("[V1::Auth::RegistrationsController#create] #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.first(10).join("\n")) if e.backtrace

        payload = { error: "Could not complete registration" }
        payload[:details] = "#{e.class}: #{e.message}" if Rails.env.development?

        render json: payload, status: :unprocessable_content
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
          :current_organization_id,
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
        render json: { errors: doctor.errors.full_messages }, status: :unprocessable_content
      end
    end
  end
end
