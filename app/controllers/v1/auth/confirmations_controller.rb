module V1
  module Auth
    class ConfirmationsController < Devise::ConfirmationsController
      respond_to :json

      def show
        self.resource = resource_class.confirm_by_token(params[:confirmation_token].to_s)

        if resource.errors.empty?
          render json: { message: "Email confirmed successfully" }, status: :ok
        else
          render json: { errors: resource.errors.full_messages }, status: :unprocessable_entity
        end
      end

      def create
        self.resource = resource_class.send_confirmation_instructions(resource_params)

        if successfully_sent?(resource)
          render json: { message: "Confirmation instructions sent" }, status: :ok
        else
          render json: { errors: resource.errors.full_messages }, status: :unprocessable_entity
        end
      end

      private

      def resource_params
        params.require(:doctor).permit(:email)
      end
    end
  end
end
