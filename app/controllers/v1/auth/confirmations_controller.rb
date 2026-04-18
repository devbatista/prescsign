module V1
  module Auth
    class ConfirmationsController < Devise::ConfirmationsController
      respond_to :json
      before_action :enforce_confirmation_show_rate_limit!, only: :show
      before_action :enforce_confirmation_create_rate_limit!, only: :create

      def show
        self.resource = resource_class.confirm_by_token(params[:confirmation_token].to_s)

        if resource.errors.empty?
          render_success(data: { message: "Email confirmed successfully" })
        else
          render_error(resource.errors.full_messages, status: :unprocessable_content)
        end
      end

      def create
        self.resource = resource_class.send_confirmation_instructions(resource_params)

        if successfully_sent?(resource)
          render_success(data: { message: "Confirmation instructions sent" })
        else
          render_error(resource.errors.full_messages, status: :unprocessable_content)
        end
      end

      private

      def resource_params
        params.fetch(:user, params.fetch(:doctor, {})).permit(:email)
      end

      def enforce_confirmation_show_rate_limit!
        enforce_named_rate_limit!(:auth_confirmation_show)
      end

      def enforce_confirmation_create_rate_limit!
        enforce_named_rate_limit!(:auth_confirmation_create)
      end
    end
  end
end
