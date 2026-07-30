module Admin
  # Registration invitations across the platform. Lista os convites de cadastro
  # de responsável (OrganizationRegistrationInvitation), reenvia (novo token +
  # e-mail) e revoga. Escrita restrita a admin (ver require_platform_writer!).
  class InvitationsController < Admin::BaseController
    before_action :set_invitation, only: %i[resend revoke]
    before_action :require_platform_writer!, only: %i[resend revoke]

    def index
      scope = OrganizationRegistrationInvitation
              .includes(:organization, :invited_by_user)
              .order(created_at: :desc)
      scope = apply_filters(scope)
      @invitations, @page, @total_pages, @total = paginate(scope)
    end

    def resend
      if @invitation.accepted?
        return redirect_to admin_invitations_path(request.query_parameters),
          alert: "Este convite já foi aceito."
      end

      ::Organizations::ResponsibleInvitationService.new(
        organization: @invitation.organization,
        invited_email: @invitation.invited_email,
        invited_by_user: current_user
      ).call

      # Supersede o convite anterior: expira o token antigo para não ficarem dois
      # convites pendentes válidos para o mesmo e-mail.
      @invitation.update!(expires_at: Time.current)

      redirect_to admin_invitations_path(request.query_parameters),
        notice: "Convite reenviado para #{@invitation.invited_email}."
    end

    def revoke
      if @invitation.accepted?
        redirect_to admin_invitations_path(request.query_parameters),
          alert: "Este convite já foi aceito e não pode ser revogado."
      else
        @invitation.update!(expires_at: Time.current)
        redirect_to admin_invitations_path(request.query_parameters),
          notice: "Convite revogado."
      end
    end

    private

    def set_invitation
      @invitation = OrganizationRegistrationInvitation.find(params[:id])
    end

    def apply_filters(scope)
      @query = params[:q].to_s.strip
      @status = params[:status].to_s.strip

      scope = scope.where("LOWER(invited_email) LIKE ?", "%#{@query.downcase}%") if @query.present?

      case @status
      when "pending"
        scope = scope.pending
      when "accepted"
        scope = scope.where.not(accepted_at: nil)
      when "expired"
        scope = scope.where(accepted_at: nil).where("expires_at <= ?", Time.current)
      end
      scope
    end
  end
end
