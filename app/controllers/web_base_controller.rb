# Base controller for the server-rendered web layer (ERB views).
#
# Coexists with the legacy API base (ApplicationController < ActionController::API)
# during the migration. Once /api/v1 is removed (Fase 5), this becomes the single
# ApplicationController.
class WebBaseController < ActionController::Base
  include ::Pundit::Authorization

  layout "application"

  protect_from_forgery with: :exception

  # Web layer is authenticated by default (session/cookie). Public pages and the
  # auth flow (login/registration/password/confirmation) skip this explicitly.
  before_action :authenticate_user!

  rescue_from ::Pundit::NotAuthorizedError, with: :render_forbidden

  private

  def render_forbidden
    render "pages/forbidden", status: :forbidden
  end
end
