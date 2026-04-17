require "pundit"

class ApplicationController < ActionController::API
  include ::Pundit::Authorization

  around_action :log_request_observability

  rescue_from ::Pundit::NotAuthorizedError, with: :render_forbidden

  private

  def pundit_user
    resolve_current_tenant_context if doctor_signed_in?
    current_doctor
  end

  def current_organization
    resolve_current_tenant_context if doctor_signed_in?
    Current.organization
  end

  def current_membership
    resolve_current_tenant_context if doctor_signed_in?
    Current.membership
  end

  def render_forbidden
    render_error("You are not authorized to perform this action", status: :forbidden)
  end

  def ensure_tenant_context!
    resolve_current_tenant_context
    return if Current.organization.present?

    render_error("No active organization available for current doctor", status: :forbidden)
  end

  def resolve_current_tenant_context
    return if Current.doctor == current_doctor && Current.organization.present?

    requested_organization_id = request.headers["X-Organization-Id"].presence
    memberships = current_doctor.active_organization_memberships
                                .joins(:organization)
                                .merge(Organization.where(active: true))
                                .includes(:organization)
    membership = if requested_organization_id.present?
      memberships.find_by(organization_id: requested_organization_id)
    elsif current_doctor.current_organization_id.present?
      memberships.find_by(organization_id: current_doctor.current_organization_id)
    else
      memberships.first
    end

    return if membership.nil?

    Current.doctor = current_doctor
    Current.organization = membership.organization
    Current.membership = membership

  end

  def log_request_observability
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    status = nil

    yield
    status = response&.status
  rescue StandardError => e
    status = 500
    Observability::CriticalAlertService.notify!(
      category: "http_500",
      exception: e,
      context: {
        request_id: request.request_id,
        endpoint: "#{request.request_method} #{request.path}",
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
      endpoint: "#{request.request_method} #{request.path}",
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
    Rails.logger.info(
      event: "http_request",
      request_id: request.request_id,
      user: observability_user,
      endpoint: "#{request.request_method} #{request.path}",
      latency_ms: latency_ms,
      status_http: status || response&.status || 500
    )
  end

  def observability_user
    return "anonymous" unless doctor_signed_in?

    {
      id: current_doctor.id,
      role: Current.membership&.role
    }.compact
  end

  def render_success(data:, status: :ok, meta: nil, legacy: true)
    payload = { data: data }
    payload[:meta] = meta if meta.present?

    # Transitional compatibility with current clients while we migrate fully to envelope-only.
    if legacy && data.is_a?(Hash)
      data.each { |key, value| payload[key] = value unless payload.key?(key) }
    end

    render json: payload, status: status
  end

  def render_error(errors, status:, meta: nil, details: nil)
    normalized_errors = Array(errors).flatten.compact.map(&:to_s)
    payload = { errors: normalized_errors }
    payload[:error] = normalized_errors.first if normalized_errors.any?
    payload[:meta] = meta if meta.present?
    payload[:details] = details if details.present?
    if meta.is_a?(Hash)
      meta.each { |key, value| payload[key] = value unless payload.key?(key) }
    end

    render json: payload, status: status
  end
end
