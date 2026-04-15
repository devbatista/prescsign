module V1
  class OrganizationsController < ApplicationController
    before_action :authenticate_doctor!
    before_action :ensure_tenant_context!

    def index
      memberships = current_doctor.active_organization_memberships
                                  .joins(:organization)
                                  .merge(Organization.where(active: true))
                                  .includes(organization: :units)
                                  .order(created_at: :asc)

      render json: {
        current_organization_id: current_organization.id,
        organizations: memberships.map { |membership| membership_payload(membership) }
      }, status: :ok
    end

    def switch
      membership = current_doctor.active_organization_memberships
                                 .joins(:organization)
                                 .merge(Organization.where(active: true))
                                 .includes(organization: :units)
                                 .find_by(
        organization_id: params[:organization_id]
      )
      return render_not_found if membership.nil?

      current_doctor.update!(current_organization_id: membership.organization_id)
      Current.organization = membership.organization
      Current.membership = membership

      render json: {
        current_organization_id: membership.organization_id,
        organization: organization_payload(membership.organization),
        membership: {
          role: membership.role,
          status: membership.status
        }
      }, status: :ok
    end

    private

    def membership_payload(membership)
      organization_payload(membership.organization).merge(
        role: membership.role,
        status: membership.status
      )
    end

    def organization_payload(organization)
      {
        id: organization.id,
        name: organization.name,
        legal_name: organization.legal_name,
        trade_name: organization.trade_name,
        cnpj: organization.cnpj,
        email: organization.email,
        phone: organization.phone,
        zip_code: organization.zip_code,
        street: organization.street,
        number: organization.number,
        complement: organization.complement,
        district: organization.district,
        city: organization.city,
        state: organization.state,
        country: organization.country,
        kind: organization.kind,
        active: organization.active,
        metadata: organization.metadata,
        units: organization.units.sort_by(&:created_at).map { |unit| unit_payload(unit) }
      }
    end

    def unit_payload(unit)
      {
        id: unit.id,
        name: unit.name,
        code: unit.code,
        active: unit.active
      }
    end

    def render_not_found
      render json: { error: "Organization not found for current doctor" }, status: :not_found
    end
  end
end
