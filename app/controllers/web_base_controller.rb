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
  before_action :set_current_tenant

  rescue_from ::Pundit::NotAuthorizedError, with: :render_forbidden

  helper_method :current_organization, :current_membership, :current_persona,
                :available_organizations, :access_context

  private

  # Resolves the active organization from the session (falls back to the user's
  # current org or first active membership) and populates Current.
  def set_current_tenant
    return unless user_signed_in?

    Current.user = current_user
    membership = resolve_membership
    return if membership.nil?

    Current.organization = membership.organization
    Current.membership = membership
    session[:current_organization_id] = membership.organization_id
  end

  def resolve_membership
    scope = active_memberships
    requested = session[:current_organization_id].presence || current_user.current_organization_id.presence
    (requested && scope.find_by(organization_id: requested)) || scope.first
  end

  def active_memberships
    current_user.organization_memberships.active
                .joins(:organization)
                .merge(Organization.where(active: true))
                .includes(:organization)
  end

  def current_organization
    Current.organization
  end

  def current_membership
    Current.membership
  end

  def available_organizations
    @available_organizations ||= active_memberships.map(&:organization)
  end

  def access_context
    @access_context ||= AccessContext.new(user: current_user, membership: current_membership)
  end

  def current_persona
    access_context.persona
  end

  # Use as a before_action on pages that require an active organization context.
  def ensure_active_organization!
    return if current_organization.present?

    redirect_to organization_context_required_path
  end

  def render_forbidden
    render "pages/forbidden", status: :forbidden
  end
end
