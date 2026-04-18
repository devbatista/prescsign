module V1
  module Auth
    class SessionsController < ApplicationController
      before_action :enforce_login_rate_limit!, only: :create

      def create
        doctor = Doctor.find_for_database_authentication(email: login_params[:email].to_s.strip.downcase)
        return render_unauthorized unless doctor&.valid_password?(login_params[:password])
        return render_unconfirmed unless doctor.active_for_authentication?

        access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)
        refresh_token = ::Auth::RefreshTokenService.issue_for(doctor)
        render_success(data: {
          access_token: access_token,
          refresh_token: refresh_token,
          doctor: doctor_payload(doctor)
        })
      end

      def destroy
        token = request.authorization.to_s.split(" ").last
        revoke_access_token(token) if token.present?
        revoke_refresh_tokens_for_current_doctor
        head :no_content
      rescue JWT::DecodeError, JWT::VerificationError, JWT::ExpiredSignature
        head :no_content
      end

      private

      def revoke_access_token(token)
        payload = Warden::JWTAuth::TokenDecoder.new.call(token)
        JwtDenylist.revoke_jwt(payload, nil)
      end

      def revoke_refresh_tokens_for_current_doctor
        doctor = current_doctor_from_token
        return unless doctor

        doctor.auth_refresh_tokens.active.find_each(&:revoke!)
      end

      def current_doctor_from_token
        token = request.authorization.to_s.split(" ").last
        return if token.blank?

        payload = Warden::JWTAuth::TokenDecoder.new.call(token)
        doctor_id = payload.dig("sub")
        return if doctor_id.blank?

        Doctor.find_by(id: doctor_id)
      rescue JWT::DecodeError, JWT::VerificationError, JWT::ExpiredSignature
        nil
      end

      def login_params
        params.require(:doctor).permit(:email, :password)
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

      def render_unauthorized
        render_error("Invalid email or password", status: :unauthorized)
      end

      def render_unconfirmed
        render_error("Please confirm your email before logging in", status: :unauthorized)
      end

      def enforce_login_rate_limit!
        enforce_named_rate_limit!(:auth_login)
      end
    end
  end
end
