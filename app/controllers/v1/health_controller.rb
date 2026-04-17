module V1
  class HealthController < ApplicationController
    def show
      render_success(data: { status: "ok" })
    end
  end
end
