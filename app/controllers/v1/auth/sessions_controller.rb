module V1
  module Auth
    class SessionsController < ApplicationController
      before_action :enforce_login_rate_limit!, only: :create

      def create
        user = User.find_for_database_authentication(email: login_params[:email].to_s.strip.downcase)
        return render_unauthorized unless user&.valid_password?(login_params[:password])
        return render_unconfirmed unless user.confirmed?
        return render_inactive unless user.status == "active"

        access_token, = Warden::JWTAuth::UserEncoder.new.call(user, :user, nil)
        refresh_token = ::Auth::RefreshTokenService.issue_for(user: user)

        render_success(data: {
          access_token: access_token,
          refresh_token: refresh_token,
          doctor: doctor_payload(user.doctor_profile),
          user: user_payload(user)
        })
      end

      def destroy
        token = request.authorization.to_s.split(" ").last
        revoke_access_token(token) if token.present?
        revoke_refresh_tokens_for_current_user(token)
        head :no_content
      rescue JWT::DecodeError, JWT::VerificationError, JWT::ExpiredSignature
        head :no_content
      end

      private

      def revoke_access_token(token)
        payload = Warden::JWTAuth::TokenDecoder.new.call(token)
        JwtDenylist.revoke_jwt(payload, nil)
      end

      def revoke_refresh_tokens_for_current_user(token)
        return if token.blank?

        payload = Warden::JWTAuth::TokenDecoder.new.call(token)
        user_id = payload.dig("sub")
        return if user_id.blank?

        user = User.find_by(id: user_id)
        return if user.nil?

        user.auth_refresh_tokens.active.find_each(&:revoke!)
      rescue JWT::DecodeError, JWT::VerificationError, JWT::ExpiredSignature
        nil
      end

      def login_params
        params.fetch(:user, params.fetch(:doctor, {})).permit(:email, :password)
      end

      def doctor_payload(profile)
        return nil if profile.nil?

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
          current_organization_id: profile.user.current_organization_id,
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
        render_error("Invalid email or password", status: :unauthorized)
      end

      def render_unconfirmed
        render_error("Please confirm your email before logging in", status: :unauthorized)
      end

      def render_inactive
        render_error("Account is inactive", status: :unauthorized)
      end

      def enforce_login_rate_limit!
        enforce_named_rate_limit!(:auth_login)
      end
    end
  end
end
