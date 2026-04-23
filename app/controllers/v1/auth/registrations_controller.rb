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
        profile = DoctorProfile.new(
          user: user,
          full_name: attrs[:full_name],
          email: attrs[:email],
          cpf: attrs[:cpf],
          license_number: attrs[:license_number],
          license_state: attrs[:license_state],
          specialty: attrs[:specialty],
          gender: attrs[:gender],
          active: true
        )

        return render_unprocessable(user) unless user.valid?
        return render_unprocessable(profile) unless profile.valid?

        ActiveRecord::Base.transaction do
          user.skip_confirmation_notification!
          user.save!
          profile.save!

          role = user.user_roles.find_or_initialize_by(role: "doctor")
          role.status = "active"
          role.save! if role.new_record? || role.changed?

          organization = Organization.create!(
            name: "Autônomo - #{profile.full_name}",
            kind: "autonomo",
            active: true
          )
          OrganizationMembership.create!(
            user: user,
            organization: organization,
            role: "owner",
            status: "active"
          )
          user.update_column(:current_organization_id, organization.id)

          user.send_confirmation_instructions
        end

        render_success(data: {
          message: "Registration successful. Please confirm your email.",
          doctor: doctor_payload(profile),
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
          :gender,
          :password,
          :password_confirmation
        )
      end

      def doctor_payload(profile)
        user = profile.user

        profile.slice(
          :id,
          :full_name,
          :email,
          :license_number,
          :license_state,
          :specialty,
          :active,
          :created_at,
          :updated_at
        ).merge(
          gender: profile.gender_label,
          current_organization_id: user.current_organization_id,
          role: user.membership_for(user.current_organization_id)&.role,
          cpf_masked: masked_cpf(profile.cpf),
          professional_title: profile.professional_title,
          welcome_prefix: profile.welcome_prefix
        )
      end

      def user_payload(user)
        {
          id: user.id,
          email: user.email,
          status: user.status,
          doctor_profile_id: user.doctor_profile&.id,
          current_organization_id: user.current_organization_id,
          roles: user.user_roles.active.pluck(:role)
        }
      end

      def masked_cpf(cpf)
        digits = cpf.to_s.gsub(/\D/, "")
        return nil if digits.length < 11

        "***.***.***-#{digits[-2, 2]}"
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
