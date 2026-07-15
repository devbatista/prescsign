# Base controller for the server-rendered web layer (ERB views). Session auth
# (Devise), Pundit authorization and tenant-by-session live here.
class ApplicationController < ActionController::Base
  include ::Pundit::Authorization

  layout "application"

  protect_from_forgery with: :exception

  # Wraps the whole request (including the before_actions below) for structured
  # observability logging + critical alerting on 500s.
  around_action :log_request_observability

  # Web layer is authenticated by default (session/cookie). Public pages and the
  # auth flow (login/registration/password/confirmation) skip this explicitly.
  before_action :authenticate_user!
  before_action :set_current_tenant
  before_action :require_organization_selection

  rescue_from ::Pundit::NotAuthorizedError, with: :render_forbidden

  helper_method :current_organization, :current_membership, :current_persona,
                :available_organizations, :access_context

  DEFAULT_PER_PAGE = 20

  private

  # Lightweight offset pagination for index screens.
  # Returns [records, page, total_pages, total_count].
  def paginate(scope, per_page: DEFAULT_PER_PAGE)
    page = params[:page].to_i
    page = 1 if page < 1
    total = scope.count
    total_pages = [(total.to_f / per_page).ceil, 1].max
    records = scope.offset((page - 1) * per_page).limit(per_page)
    [records, page, total_pages, total]
  end

  # Resolves the active organization from the session (falls back to the user's
  # current org or first active membership) and populates Current.
  def set_current_tenant
    return unless user_signed_in?

    Current.user = current_user
    memberships = active_memberships
    return if organization_selection_required?(memberships)

    membership = resolve_membership(memberships)
    return if membership.nil?

    Current.organization = membership.organization
    Current.membership = membership
    session[:current_organization_id] = membership.organization_id
  end

  def resolve_membership(scope = active_memberships)
    requested = session[:current_organization_id].presence || current_user.current_organization_id.presence
    (requested && scope.find_by(organization_id: requested)) || scope.first
  end

  def require_organization_selection
    return unless user_signed_in?
    return unless organization_selection_required?
    return if organization_selection_allowed_action?

    redirect_to select_organization_path
  end

  def organization_selection_required?(memberships = active_memberships)
    session[:organization_selection_required].present? &&
      session[:current_organization_id].blank? &&
      memberships.many?
  end

  def organization_selection_allowed_action?
    return true if controller_path == "sessions" && action_name == "destroy"
    return false unless controller_path == "app/organizations"

    action_name.in?(%w[select choose switch])
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
    render "shared/forbidden", status: :forbidden
  end

  # Structured request logging + critical alerting. Times the request, emits an
  # http_endpoint_monitor / http_request line always, and on an unhandled
  # exception notifies Observability::CriticalAlertService and logs http_error.
  def log_request_observability
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status = nil
    endpoint = "#{request.request_method} #{request.path}"

    yield
    status = response&.status
  rescue StandardError => e
    status = 500
    Observability::CriticalAlertService.notify!(
      category: "http_500",
      exception: e,
      context: {
        request_id: request.request_id,
        endpoint: endpoint,
        user: observability_user,
        organization_id: Current.organization&.id,
        membership_role: Current.membership&.role
      }
    )
    Rails.logger.error(
      event: "http_error",
      request_id: request.request_id,
      user: observability_user,
      organization_id: Current.organization&.id,
      membership_role: Current.membership&.role,
      endpoint: endpoint,
      status_http: status,
      ip_address: request.remote_ip,
      user_agent: request.user_agent,
      params: request.filtered_parameters.except("controller", "action"),
      error_class: e.class.name,
      error_message: e.message,
      backtrace: e.backtrace&.first(20)
    )
    raise
  ensure
    latency_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000.0).round(2)
    final_status = status || response&.status || 500
    monitor_payload = {
      event: "http_endpoint_monitor",
      request_id: request.request_id,
      endpoint: endpoint,
      method: request.request_method,
      path: request.path,
      status_http: final_status,
      status_family: (final_status.to_i / 100),
      latency_ms: latency_ms,
      slow_request: latency_ms >= slow_request_threshold_ms,
      rollout_phase: observability_rollout_phase,
      organization_id: Current.organization&.id,
      membership_role: Current.membership&.role,
      user: observability_user
    }.compact

    Rails.logger.info(monitor_payload)
    Rails.logger.warn(monitor_payload.merge(event: "http_slow_request")) if monitor_payload[:slow_request]
  end

  def observability_user
    return "anonymous" unless user_signed_in?

    {
      user_id: current_user&.id,
      membership_role: Current.membership&.role,
      user_roles: current_user&.user_roles&.active&.pluck(:role)
    }.compact
  end

  def slow_request_threshold_ms
    configured = Rails.application.config.x.observability.slow_request_threshold_ms.to_f
    configured.positive? ? configured : 1200.0
  end

  def observability_rollout_phase
    Rails.application.config.x.observability.rollout_phase
  end
end
