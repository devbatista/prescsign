module Auth
  class RefreshTokensController < ApplicationController
    def create
      refresh_token = params[:refresh_token].to_s
      return render_unauthorized if refresh_token.blank?

      refresh_token_record = RefreshTokenService.find_active(refresh_token)
      return render_unauthorized unless refresh_token_record

      doctor = refresh_token_record.doctor
      refresh_token_record.revoke!

      access_token, = Warden::JWTAuth::UserEncoder.new.call(doctor, :doctor, nil)
      next_refresh_token = RefreshTokenService.issue_for(doctor)

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

    def render_unauthorized
      render json: { error: "Invalid refresh token" }, status: :unauthorized
    end
  end
end
