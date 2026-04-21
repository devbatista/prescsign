module V1
  module Auth
    class RefreshTokensController < ApplicationController
      before_action :enforce_refresh_rate_limit!, only: :create

      def create
        refresh_token = params[:refresh_token].to_s
        return render_unauthorized if refresh_token.blank?

        refresh_token_record = ::Auth::RefreshTokenService.find_active(refresh_token)
        return render_unauthorized unless refresh_token_record

        user = refresh_token_record.user
        return render_unauthorized if user.nil? || !user.confirmed? || user.status != "active"

        access_token = nil
        next_refresh_token = nil

        ActiveRecord::Base.transaction do
          refresh_token_record.revoke!
          access_token, = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
          next_refresh_token = ::Auth::RefreshTokenService.issue_for(user: user)
        end

        render_success(data: {
          access_token: access_token,
          refresh_token: next_refresh_token,
          doctor: doctor_payload(user.doctor_profile),
          user: user_payload(user)
        })
      end

      private

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
          current_organization_id: user.current_organization_id,
          role: user.membership_for(user.current_organization_id)&.role,
          cpf_masked: masked_cpf(profile.cpf)
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

      def render_unauthorized
        render_error("Invalid refresh token", status: :unauthorized)
      end

      def enforce_refresh_rate_limit!
        enforce_named_rate_limit!(:auth_refresh)
      end
    end
  end
end
