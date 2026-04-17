module V1
  module Auth
    class RefreshTokensController < ApplicationController
      def create
        refresh_token = params[:refresh_token].to_s
        return render_unauthorized if refresh_token.blank?

        refresh_token_record = ::Auth::RefreshTokenService.find_active(refresh_token)
        return render_unauthorized unless refresh_token_record

        doctor = refresh_token_record.doctor
        access_token = nil
        next_refresh_token = nil

        ActiveRecord::Base.transaction do
          refresh_token_record.revoke!
          access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)
          next_refresh_token = ::Auth::RefreshTokenService.issue_for(doctor)
        end

        render json: {
          access_token: access_token,
          refresh_token: next_refresh_token,
          doctor: doctor_payload(doctor)
        }, status: :ok
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

      def render_unauthorized
        render json: { error: "Invalid refresh token" }, status: :unauthorized
      end
    end
  end
end
