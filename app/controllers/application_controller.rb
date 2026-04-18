require "pundit"
require "digest"

class ApplicationController < ActionController::API
  include ::Pundit::Authorization

  DEFAULT_PER_PAGE = 20
  MAX_PER_PAGE = 100

  around_action :log_request_observability

  rescue_from ::Pundit::NotAuthorizedError, with: :render_forbidden

  private

  def pundit_user
    resolve_current_tenant_context if user_signed_in?
    current_user
  end

  def current_organization
    resolve_current_tenant_context if user_signed_in?
    Current.organization
  end

  def current_membership
    resolve_current_tenant_context if user_signed_in?
    Current.membership
  end

  def render_forbidden
    render_error("You are not authorized to perform this action", status: :forbidden)
  end

  def ensure_tenant_context!
    resolve_current_tenant_context
    return if Current.organization.present?

    render_error("No active organization available for current actor", status: :forbidden)
  end

  def resolve_current_tenant_context
    return unless user_signed_in?
    return if Current.user == current_user && Current.organization.present?

    requested_organization_id = request.headers["X-Organization-Id"].presence
    memberships = current_user.organization_memberships.active
                                .joins(:organization)
                                .merge(Organization.where(active: true))
                                .includes(:organization)
    membership = if requested_organization_id.present?
      memberships.find_by(organization_id: requested_organization_id)
    elsif current_user.current_organization_id.present?
      memberships.find_by(organization_id: current_user.current_organization_id)
    else
      memberships.first
    end

    return if membership.nil?

    Current.user = current_user
    Current.doctor = current_user.doctor
    Current.organization = membership.organization
    Current.membership = membership

  end

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

    Rails.logger.info(
      event: "http_request",
      request_id: request.request_id,
      user: observability_user,
      endpoint: endpoint,
      latency_ms: latency_ms,
      status_http: final_status,
      rollout_phase: observability_rollout_phase
    )
  end

  def observability_user
    return "anonymous" unless user_signed_in?

    {
      user_id: current_user&.id,
      doctor_id: current_doctor_for_context&.id,
      membership_role: Current.membership&.role,
      user_roles: current_user&.user_roles&.active&.pluck(:role)
    }.compact
  end

  def current_doctor_for_context
    current_user&.doctor
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

  def enforce_named_rate_limit!(name)
    config = Rails.application.config.x.rate_limits.fetch(name)
    enforce_rate_limit!(
      bucket: name,
      limit: config.fetch(:limit),
      period: config.fetch(:period),
      identifier: request.remote_ip.to_s.presence || "unknown"
    )
  end

  def enforce_rate_limit!(bucket:, limit:, period:, identifier:)
    hit_count = Prescsign::RateLimiter.hit!(
      bucket: bucket,
      identifier: identifier,
      period: period
    )
    return true if hit_count <= limit

    response.set_header("Retry-After", period.to_i.to_s)
    render_error(
      "Rate limit exceeded. Try again later.",
      status: :too_many_requests,
      meta: { retry_after: period.to_i }
    )
    false
  end

  def with_idempotency(scope:)
    record = nil
    created = false
    key = request.headers["Idempotency-Key"].presence || request.headers["HTTP_IDEMPOTENCY_KEY"].presence
    key = key.to_s.strip
    return yield if key.blank?
    return yield unless user_signed_in?
    return yield if current_organization.blank?

    fingerprint = idempotency_request_fingerprint
    record, created = find_or_create_idempotency_record!(
      scope: scope,
      key: key,
      fingerprint: fingerprint
    )

    unless created
      return render_idempotency_conflict("Idempotency-Key already used with different payload") if record.request_fingerprint != fingerprint

      if idempotency_replayable?(record)
        response.set_header("Idempotency-Replayed", "true")
        render json: record.response_body, status: record.status_code
      else
        render_idempotency_conflict("Request with this Idempotency-Key is already being processed")
      end
      return
    end

    yield

    persist_idempotency_response!(record)
  rescue StandardError
    cleanup_unfinished_idempotency_record!(record, created)
    raise
  end

  def find_or_create_idempotency_record!(scope:, key:, fingerprint:)
    record = IdempotencyKey.find_or_initialize_by(
      user_id: current_user.id,
      doctor_id: current_doctor_for_context&.id,
      organization_id: current_organization.id,
      scope: scope.to_s,
      key: key
    )
    return [record, false] unless record.new_record?

    record.request_fingerprint = fingerprint
    record.save!
    [record, true]
  rescue ActiveRecord::RecordNotUnique
    record = IdempotencyKey.find_by!(
      user_id: current_user.id,
      organization_id: current_organization.id,
      scope: scope.to_s,
      key: key
    )
    [record, false]
  end

  def idempotency_request_fingerprint
    Digest::SHA256.hexdigest(
      [
        request.request_method.to_s.upcase,
        request.path.to_s,
        request.raw_post.to_s
      ].join("|")
    )
  end

  def idempotency_replayable?(record)
    record.status_code.to_i.positive?
  end

  def persist_idempotency_response!(record)
    return unless response.status.to_i.between?(200, 299)

    record.update!(
      status_code: response.status.to_i,
      response_body: parse_idempotency_response_body
    )
  end

  def parse_idempotency_response_body
    JSON.parse(response.body)
  rescue JSON::ParserError
    { "raw" => response.body.to_s }
  end

  def cleanup_unfinished_idempotency_record!(record, created)
    return unless created
    return if record.nil? || !record.persisted?
    return if record.status_code.to_i.positive?

    record.destroy!
  rescue StandardError
    nil
  end

  def render_idempotency_conflict(message)
    render_error(message, status: :conflict)
  end

  def slow_request_threshold_ms
    configured = Rails.application.config.x.observability.slow_request_threshold_ms.to_f
    configured.positive? ? configured : 1200.0
  end

  def observability_rollout_phase
    Rails.application.config.x.observability.rollout_phase
  end
end
