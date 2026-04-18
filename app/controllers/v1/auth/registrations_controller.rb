module V1
  module Auth
    class RegistrationsController < ApplicationController
      before_action :enforce_registration_rate_limit!, only: :create

      def create
        doctor = Doctor.new(registration_params)
        return render_unprocessable(doctor) unless doctor.valid?

        ActiveRecord::Base.transaction do
          doctor.skip_confirmation_notification!
          doctor.save!
          doctor.send_confirmation_instructions
        end

        render_success(data: {
          message: "Registration successful. Please confirm your email.",
          doctor: doctor_payload(doctor)
        }, status: :created)
      rescue StandardError => e
        Rails.logger.error("[V1::Auth::RegistrationsController#create] #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.first(10).join("\n")) if e.backtrace

        details = Rails.env.development? ? "#{e.class}: #{e.message}" : nil
        render_error("Could not complete registration", status: :unprocessable_content, details: details)
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
          :license_number,
          :license_state,
          :specialty,
          :active,
          :created_at,
          :updated_at
        ).merge(cpf_masked: doctor.masked_cpf)
      end

      def render_unprocessable(doctor)
        render_error(doctor.errors.full_messages, status: :unprocessable_content)
      end

      def enforce_registration_rate_limit!
        enforce_named_rate_limit!(:auth_register)
      end
    end
  end
end
