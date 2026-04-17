module V1
  module Auth
    class PasswordsController < ApplicationController
      def create
        doctor = Doctor.find_for_database_authentication(email: password_request_params[:email].to_s.strip.downcase)
        doctor&.send(:set_reset_password_token)

        render_success(data: { message: "If this email exists, reset instructions were sent" })
      end

      def update
        doctor = Doctor.reset_password_by_token(password_update_params)

        if doctor.errors.empty?
          render_success(data: { message: "Password updated successfully" })
        else
          render_error(doctor.errors.full_messages, status: :unprocessable_content)
        end
      end

      private

      def password_request_params
        params.require(:doctor).permit(:email)
      end

      def password_update_params
        params.require(:doctor).permit(:reset_password_token, :password, :password_confirmation)
      end
    end
  end
end
