module V1
  module Auth
    class RegistrationsController < ApplicationController
      DOCTOR_PROFILE_FIELDS = %i[
        full_name
        cpf
        license_number
        license_state
        specialty
        gender
      ].freeze

      before_action :enforce_registration_rate_limit!, only: %i[create validate]

      def validate
        invitation = find_pending_invitation(params[:invitation_token])
        return render_error("Invalid or expired invitation token", status: :unprocessable_content) if invitation.nil?

        if params[:email].present? && invitation.invited_email.to_s.downcase != params[:email].to_s.downcase
          return render_error("Invitation token does not match informed email", status: :unprocessable_content)
        end

        render_success(data: {
          valid: true,
          invited_email: invitation.invited_email,
          responsible_email: invitation.invited_email,
          organization_id: invitation.organization_id,
          organization: {
            id: invitation.organization_id,
            name: invitation.organization.name
          },
          expires_at: invitation.expires_at
        })
      end

      def create
        attrs = registration_params
        invitation = resolve_invitation!(
          token: attrs[:invitation_token],
          email: attrs[:email],
          organization_id: attrs[:organization_id]
        )
        return if performed?

        user = User.new(
          email: attrs[:email],
          password: attrs[:password],
          password_confirmation: attrs[:password_confirmation],
          status: "active"
        )
        profile = nil

        if doctor_profile_requested?(attrs)
          doctor_attrs = doctor_profile_registration_params(attrs)
          profile = DoctorProfile.new(
            user: user,
            full_name: doctor_attrs[:full_name],
            email: attrs[:email],
            cpf: doctor_attrs[:cpf],
            license_number: doctor_attrs[:license_number],
            license_state: doctor_attrs[:license_state],
            specialty: doctor_attrs[:specialty],
            gender: doctor_attrs[:gender],
            active: true
          )
        end

        return render_unprocessable(user) unless user.valid?
        return render_unprocessable(profile) if profile.present? && !profile.valid?

        ActiveRecord::Base.transaction do
          user.skip_confirmation_notification!
          user.save!
          profile&.save!

          ensure_role!(user: user, role_name: "manager")
          ensure_role!(user: user, role_name: "doctor") if profile.present?

          OrganizationMembership.create!(
            user: user,
            organization: invitation.organization,
            role: "admin",
            status: "active"
          )
          OrganizationResponsible.find_or_create_by!(organization: invitation.organization, user: user)
          user.update_column(:current_organization_id, invitation.organization_id)
          invitation.mark_accepted!(user: user)

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
        attrs = params.fetch(:user, params.fetch(:doctor, {})).permit(
          :full_name,
          :email,
          :cpf,
          :license_number,
          :license_state,
          :specialty,
          :gender,
          :password,
          :password_confirmation,
          :invitation_token,
          :organization_id
        ).to_h.symbolize_keys

        attrs[:invitation_token] = params[:invitation_token].to_s if attrs[:invitation_token].blank? && params[:invitation_token].present?
        attrs[:organization_id] = params[:organization_id].to_s if attrs[:organization_id].blank? && params[:organization_id].present?

        attrs
      end

      def doctor_profile_registration_params(attrs)
        nested_attrs = params.fetch(:doctor_profile, {}).permit(*DOCTOR_PROFILE_FIELDS).to_h.symbolize_keys
        return nested_attrs if nested_attrs.present?

        attrs.slice(*DOCTOR_PROFILE_FIELDS)
      end

      def doctor_profile_requested?(attrs)
        return true if params.key?(:doctor_profile)

        doctor_attrs = attrs.slice(*DOCTOR_PROFILE_FIELDS)
        doctor_attrs.except(:full_name).values.any?(&:present?)
      end

      def ensure_role!(user:, role_name:)
        role = user.user_roles.find_or_initialize_by(role: role_name)
        role.status = "active"
        role.save! if role.new_record? || role.changed?
      end

      def resolve_invitation!(token:, email:, organization_id: nil)
        invitation = find_pending_invitation(token)
        if invitation.nil?
          render_error("Invalid or expired invitation token", status: :unprocessable_content)
          return nil
        end

        if invitation.invited_email.to_s.downcase != email.to_s.downcase
          render_error("Invitation token does not match informed email", status: :unprocessable_content)
          return nil
        end

        if organization_id.present? && invitation.organization_id != organization_id
          render_error("Invitation token does not match informed organization", status: :unprocessable_content)
          return nil
        end

        invitation
      end

      def find_pending_invitation(token)
        OrganizationRegistrationInvitation.find_pending_by_raw_token(token)
      end

      def doctor_payload(profile)
        return nil if profile.nil?

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
