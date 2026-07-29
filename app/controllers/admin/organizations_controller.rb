module Admin
  # Cross-organization management for the platform back-office. Lists every
  # organization (não é multi-tenant aqui — o admin enxerga todas), abre os
  # detalhes e ativa/desativa. Escrita restrita a admin (ver require_platform_writer!).
  class OrganizationsController < Admin::BaseController
    before_action :set_organization, only: %i[show activate deactivate]
    before_action :require_platform_writer!, only: %i[activate deactivate]

    def index
      scope = Organization.order(:name)
      scope = apply_filters(scope)
      @organizations, @page, @total_pages, @total = paginate(scope)
    end

    def show
      @units = @organization.units.order(:name)
      @counts = {
        members: @organization.organization_memberships.where(status: "active").count,
        doctors: @organization.organization_memberships.where(role: "doctor", status: "active").count,
        patients: @organization.patients.count,
        documents: @organization.documents.count,
        pending_invitations: @organization.organization_registration_invitations.pending.count
      }
    end

    def activate
      @organization.update!(active: true)
      redirect_to admin_organization_path(@organization), notice: "Organização ativada."
    end

    def deactivate
      @organization.update!(active: false)
      redirect_to admin_organization_path(@organization), notice: "Organização desativada."
    end

    private

    def set_organization
      @organization = Organization.find(params[:id])
    end

    def apply_filters(scope)
      @query = params[:q].to_s.strip
      @status = params[:status].to_s.strip

      if @query.present?
        term = "%#{@query.downcase}%"
        scope = scope.where(
          "LOWER(name) LIKE :t OR LOWER(COALESCE(legal_name, '')) LIKE :t OR COALESCE(cnpj, '') LIKE :t",
          t: term
        )
      end

      scope = scope.where(active: true) if @status == "active"
      scope = scope.where(active: false) if @status == "inactive"
      scope
    end
  end
end
