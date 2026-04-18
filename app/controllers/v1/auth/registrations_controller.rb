module V1
  module Auth
    class RegistrationsController < ApplicationController
      before_action :enforce_registration_rate_limit!, only: :create

      def create
        attrs = registration_params
        user = User.new(
          email: attrs[:email],
          password: attrs[:password],
          password_confirmation: attrs[:password_confirmation],
          status: "active"
        )
        doctor = Doctor.new(
          full_name: attrs[:full_name],
          email: attrs[:email],
          cpf: attrs[:cpf],
          license_number: attrs[:license_number],
          license_state: attrs[:license_state],
          specialty: attrs[:specialty],
          active: true
        )

        return render_unprocessable(user) unless user.valid?
        return render_unprocessable(doctor) unless doctor.valid?

        ActiveRecord::Base.transaction do
          user.skip_confirmation_notification!
          user.save!
          doctor.save!

          DoctorProfile.find_or_create_by!(user: user) do |profile|
            profile.doctor = doctor
            profile.cpf = doctor.cpf
            profile.license_number = doctor.license_number
            profile.license_state = doctor.license_state
            profile.specialty = doctor.specialty
          end

          LegacyDoctorUserMapping.find_or_create_by!(legacy_doctor: doctor, user: user) do |mapping|
            mapping.backfilled_at = Time.current
          end

          role = user.user_roles.find_or_initialize_by(role: "doctor")
          role.status = "active"
          role.save! if role.new_record? || role.changed?

          user.send_confirmation_instructions
        end

        render_success(data: {
          message: "Registration successful. Please confirm your email.",
          doctor: doctor_payload(doctor),
          user: user_payload(user)
        }, status: :created)
      rescue StandardError => e
        Rails.logger.error("[V1::Auth::RegistrationsController#create] #{e.class}: #{e.message}")
        Rails.logger.error(e.backtrace.first(10).join("\n")) if e.backtrace

        details = Rails.env.development? ? "#{e.class}: #{e.message}" : nil
        render_error("Could not complete registration", status: :unprocessable_content, details: details)
      end

      private

      def registration_params
        params.fetch(:user, params.fetch(:doctor, {})).permit(
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

      def user_payload(user)
        {
          id: user.id,
          email: user.email,
          status: user.status,
          doctor_id: user.doctor_id,
          current_organization_id: user.current_organization_id,
          roles: user.user_roles.active.pluck(:role)
        }
      end

      def render_unprocessable(resource)
        render_error(resource.errors.full_messages, status: :unprocessable_content)
      end

      def enforce_registration_rate_limit!
        enforce_named_rate_limit!(:auth_register)
      end
    end
  end
end
