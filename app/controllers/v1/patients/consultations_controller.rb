module V1
  module Patients
    class ConsultationsController < ApplicationController
      before_action :authenticate_user!
      before_action :ensure_tenant_context!

      def index
        render_not_implemented
      end

      def create
        render_not_implemented
      end

      private

      def render_not_implemented
        render_error("Not implemented yet", status: :not_implemented)
      end
    end
  end
end
