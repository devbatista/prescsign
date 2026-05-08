module V1
  module Agenda
    class EventsController < ApplicationController
      before_action :authenticate_user!
      before_action :ensure_tenant_context!

      def index
        authorize Consultation, :index?

        render_success(
          data: ::Agenda::EventsQuery.new(
            user: current_user,
            organization: current_organization,
            params: event_params
          ).call
        )
      end

      private

      def event_params
        params.permit(:starts_at, :ends_at, :doctor_id, :status)
      end
    end
  end
end
