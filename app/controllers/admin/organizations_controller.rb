module Admin
  # Cross-organization management for the platform back-office. Lists every
  # organization (não é multi-tenant aqui — o admin enxerga todas), abre os
  # detalhes e ativa/desativa. Escrita restrita a admin (ver require_platform_writer!).
  class OrganizationsController < Admin::BaseController
    before_action :set_organization, only: %i[show activate deactivate]
    before_action :require_platform_writer!, only: %i[new create activate deactivate]

    def index
      scope = Organization.order(:name)
      scope = apply_filters(scope)
      @organizations, @page, @total_pages, @total = paginate(scope)
    end

    def new
      @organization = Organization.new(kind: "clinica", country: "BR")
      @responsible_email = nil
    end

    # Cria a organização e dispara o convite ao responsável (início do onboarding).
    # Diferente do painel app.: o admin do back-office é cross-tenant, então NÃO
    # vira membro/owner nem troca de contexto — o vínculo nasce quando o
    # responsável aceita o convite.
    def create
      attrs = organization_params.to_h.symbolize_keys
      @responsible_email = attrs.delete(:responsible_email).to_s.strip.downcase
      attrs[:name] = attrs[:trade_name].presence || attrs[:legal_name] if attrs[:name].blank?
      @organization = Organization.new(attrs)

      if @responsible_email.blank?
        flash.now[:alert] = "Informe o e-mail do responsável."
        return render :new, status: :unprocessable_entity
      end

      ActiveRecord::Base.transaction do
        @organization.save!
        ::Organizations::ResponsibleInvitationService.new(
          organization: @organization,
          invited_email: @responsible_email,
          invited_by_user: current_user
        ).call
      end

      redirect_to admin_organization_path(@organization),
        notice: "Organização criada. Convite enviado para #{@responsible_email}."
    rescue ActiveRecord::RecordInvalid
      flash.now[:alert] = @organization.errors.full_messages.to_sentence.presence || "Não foi possível criar a organização."
      render :new, status: :unprocessable_entity
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

    def organization_params
      params.require(:organization).permit(
        :name, :legal_name, :trade_name, :cnpj, :email, :phone,
        :zip_code, :street, :number, :complement, :district, :city, :state, :country,
        :kind, :responsible_email
      )
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
