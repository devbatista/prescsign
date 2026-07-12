module App
  # Responsible doctors management within the panel (app.prescsign.local).
  # Listing = active doctor memberships of the current organization (mirrors the
  # dashboard's recent doctors query). Creation = invitation by email, reusing
  # Organizations::ResponsibleInvitationService (the direct POST /v1/doctors the
  # Vue app expected never existed in the backend).
  class ResponsibleDoctorsController < WebBaseController
    before_action :ensure_active_organization!
    before_action :require_responsible_management!

    def index
      load_doctors
      load_pending_invitations
    end

    def new
      @invited_email = nil
    end

    def create
      @invited_email = params[:invited_email].to_s.strip.downcase

      if @invited_email.blank?
        flash.now[:alert] = "Informe o e-mail do médico a convidar."
        return render :new, status: :unprocessable_entity
      end

      Organizations::ResponsibleInvitationService.new(
        organization: current_organization,
        invited_email: @invited_email,
        invited_by_user: current_user
      ).call

      redirect_to responsible_doctors_path, notice: "Convite enviado para #{@invited_email}."
    rescue ActiveRecord::RecordInvalid => e
      flash.now[:alert] = e.record.errors.full_messages.to_sentence.presence || "Não foi possível enviar o convite."
      render :new, status: :unprocessable_entity
    end

    private

    def require_responsible_management!
      render_forbidden unless access_context.can?(:responsible_doctors)
    end

    def load_doctors
      user_ids = OrganizationMembership
                 .where(organization_id: current_organization.id, role: "doctor", status: "active")
                 .pluck(:user_id)
      @doctors = DoctorProfile.where(user_id: user_ids).order(:full_name)
    end

    def load_pending_invitations
      @pending_invitations = OrganizationRegistrationInvitation
                             .pending
                             .where(organization_id: current_organization.id)
                             .order(created_at: :desc)
    end
  end
end
