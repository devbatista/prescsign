require "pundit"

class ApplicationController < ActionController::API
  include ::Pundit::Authorization

  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 100

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
    status_code = Rack::Utils.status_code(status)
    error_code = default_error_code_for(status_code)
    payload = {
      errors: normalized_errors.map { |message| { code: error_code, message: message } },
      error: normalized_errors.first,
      error_code: error_code
    }
    meta_payload = {
      request_id: request.request_id,
      status: status_code
    }
    meta_payload.merge!(meta.to_h) if meta.respond_to?(:to_h)
    payload[:meta] = meta_payload
    payload[:details] = details if details.present?
    if meta.respond_to?(:to_h)
      meta.to_h.each { |key, value| payload[key] = value unless payload.key?(key) }
    end

    render json: payload, status: status
  end

  def default_error_code_for(status_code)
    {
      400 => "bad_request",
      401 => "unauthorized",
      403 => "forbidden",
      404 => "not_found",
      422 => "unprocessable_entity",
      500 => "internal_server_error"
    }.fetch(status_code, "http_#{status_code}")
  end

  def paginate_scope(scope)
    page = normalize_page(params[:page])
    per_page = normalize_per_page(params[:per_page])
    total = scope.count
    records = scope.offset((page - 1) * per_page).limit(per_page)

    [records, total, page, per_page]
  end

  def build_pagination_meta(total:, page:, per_page:, extra: {})
    {
      page: page,
      per_page: per_page,
      total: total,
      total_pages: (total.to_f / per_page).ceil
    }.merge(extra)
  end

  def apply_standard_order(scope, allowed_sorts:, default_sort:, default_dir: :asc)
    sort_key = params[:sort_by].to_s
    sort_dir = normalize_sort_dir(params[:sort_dir], default: default_dir)
    mapped_column = allowed_sorts[sort_key] || allowed_sorts.fetch(default_sort.to_s)

    ordered_scope = scope.order(mapped_column => sort_dir)
    [ordered_scope, { sort_by: resolved_sort_key(allowed_sorts, mapped_column, default_sort), sort_dir: sort_dir }]
  end

  def normalize_page(value)
    parsed = value.to_i
    parsed.positive? ? parsed : 1
  end

  def normalize_per_page(value)
    parsed = value.to_i
    return DEFAULT_PER_PAGE if parsed <= 0

    [parsed, MAX_PER_PAGE].min
  end

  def normalize_sort_dir(value, default:)
    candidate = value.to_s.downcase
    return candidate.to_sym if %w[asc desc].include?(candidate)

    default.to_sym
  end

  def resolved_sort_key(allowed_sorts, mapped_column, default_sort)
    allowed_sorts.find { |_key, column| column == mapped_column }&.first || default_sort.to_s
  end
end
