module V1
  class ConsultationsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_tenant_context!

    def show
      render_not_implemented
    end

    def update
      render_not_implemented
    end

    def cancel
      render_not_implemented
    end

    private

    def render_not_implemented
      render_error("Not implemented yet", status: :not_implemented)
    end
  end
end
