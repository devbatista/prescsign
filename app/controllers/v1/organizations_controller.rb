module V1
  class OrganizationsController < ApplicationController
    before_action :authenticate_doctor!
    before_action :ensure_tenant_context!

    def index
      authorize Organization
      memberships = current_user.organization_memberships.active
                        .where(organization_id: policy_scope(Organization).select(:id))
                        .includes(organization: :units)
      ordered_memberships, sort_meta = apply_standard_order(
        memberships,
        allowed_sorts: {
          "created_at" => :created_at
        },
        default_sort: :created_at
      )
      records, total, page, per_page = paginate_scope(ordered_memberships)

      render_success(data: {
        current_organization_id: current_organization.id,
        organizations: records.map { |membership| membership_payload(membership) }
      }, meta: build_pagination_meta(total: total, page: page, per_page: per_page, extra: sort_meta))
    end

    def switch
      organization = policy_scope(Organization).includes(:units).find_by(id: params[:organization_id])
      return render_not_found if organization.nil?
      authorize organization, :switch?

      membership = current_user.organization_memberships.active.find_by(organization_id: organization.id)
      return render_not_found if membership.nil?

      current_doctor_for_context.update!(current_organization_id: membership.organization_id) if current_doctor_for_context.present?
      Current.organization = organization
      Current.membership = membership

      render_success(data: {
        current_organization_id: organization.id,
        organization: organization_payload(organization),
        membership: {
          role: membership.role,
          status: membership.status
        }
      })
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
      render_error("Organization not found for current user", status: :not_found)
    end
  end
end
