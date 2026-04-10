class ApplicationController < ActionController::API
  include Pundit::Authorization

  rescue_from Pundit::NotAuthorizedError, with: :render_forbidden

  private

  def pundit_user
    current_doctor
  end

  def render_forbidden
    render json: { error: "You are not authorized to perform this action" }, status: :forbidden
  end
end
