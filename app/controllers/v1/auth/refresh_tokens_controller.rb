module V1
  module Auth
    class RefreshTokensController < ApplicationController
      before_action :enforce_refresh_rate_limit!, only: :create

      def create
        refresh_token = params[:refresh_token].to_s
        return render_unauthorized if refresh_token.blank?

        refresh_token_record = ::Auth::RefreshTokenService.find_active(refresh_token)
        return render_unauthorized unless refresh_token_record

        doctor = refresh_token_record.doctor
        user = refresh_token_record.user || ::Auth::UserIdentityResolver.resolve_for_doctor(doctor)
        return render_user_identity_required if user.nil? && users_identity_required?
        access_token = nil
        next_refresh_token = nil

        ActiveRecord::Base.transaction do
          refresh_token_record.revoke!
          access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)
          next_refresh_token = ::Auth::RefreshTokenService.issue_for(doctor: doctor, user: user)
        end

        render_success(data: {
          access_token: access_token,
          refresh_token: next_refresh_token,
          doctor: doctor_payload(doctor),
          user: user_payload(user)
        })
      end

      private

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
        return nil if user.nil?

        {
          id: user.id,
          email: user.email,
          status: user.status,
          doctor_id: user.doctor_id,
          current_organization_id: user.current_organization_id,
          roles: user.user_roles.active.pluck(:role)
        }
      end

      def render_unauthorized
        render_error("Invalid refresh token", status: :unauthorized)
      end

      def render_user_identity_required
        render_error("User identity is not linked for this account", status: :unauthorized)
      end

      def enforce_refresh_rate_limit!
        enforce_named_rate_limit!(:auth_refresh)
      end

      def users_identity_required?
        Rails.application.config.x.auth.users_required
      end
    end
  end
end
