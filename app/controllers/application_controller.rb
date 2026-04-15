require "pundit"

class ApplicationController < ActionController::API
  include ::Pundit::Authorization

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
    render json: { error: "You are not authorized to perform this action" }, status: :forbidden
  end

  def ensure_tenant_context!
    resolve_current_tenant_context
    return if Current.organization.present?

    render json: { error: "No active organization available for current doctor" }, status: :forbidden
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
end
