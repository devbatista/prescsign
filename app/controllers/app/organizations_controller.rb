module App
  # Organization context within the panel (app.prescsign.local): switching the
  # active org plus creating new ones. Creation mirrors V1::OrganizationsController
  # (org + owner membership + responsible invitation) and reuses
  # Organizations::ResponsibleInvitationService.
  class OrganizationsController < ApplicationController
    def select
      @memberships = organization_choices
      redirect_to app_root_path if @memberships.one?
    end

    def choose
      membership = current_user.organization_memberships.active
                               .find_by(organization_id: params[:organization_id])

      if membership.nil?
        @memberships = organization_choices
        flash.now[:alert] = "Organização indisponível."
        return render :select, status: :unprocessable_entity
      end

      apply_organization_context!(membership)

      redirect_to app_root_path, notice: "Organização ativa: #{membership.organization.name}."
    end

    def new
      authorize Organization
      @organization = Organization.new(kind: "clinica", country: "BR")
      @responsible_email = nil
    end

    def create
      authorize Organization

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
        membership = current_user.organization_memberships.find_or_initialize_by(organization: @organization)
        membership.role = "owner" if membership.new_record?
        membership.status = "active"
        membership.save! if membership.new_record? || membership.changed?

        Organizations::ResponsibleInvitationService.new(
          organization: @organization,
          invited_email: @responsible_email,
          invited_by_user: current_user
        ).call
      end

      current_user.update!(current_organization_id: @organization.id)
      session[:current_organization_id] = @organization.id

      redirect_to app_root_path, notice: "Organização criada. Convite enviado para #{@responsible_email}."
    rescue ActiveRecord::RecordInvalid
      flash.now[:alert] = @organization.errors.full_messages.to_sentence.presence || "Não foi possível criar a organização."
      render :new, status: :unprocessable_entity
    end

    # POST /organizations/switch
    def switch
      membership = current_user.organization_memberships.active
                               .find_by(organization_id: params[:organization_id])

      if membership.nil?
        return redirect_back fallback_location: app_root_path, alert: "Organização indisponível."
      end

      apply_organization_context!(membership)

      redirect_back fallback_location: app_root_path,
        notice: "Organização ativa: #{membership.organization.name}."
    end

    private

    def organization_choices
      current_user.organization_memberships.active
                  .joins(:organization)
                  .merge(Organization.where(active: true))
                  .includes(:organization)
                  .order("organizations.name")
    end

    def apply_organization_context!(membership)
      current_user.update!(current_organization_id: membership.organization_id)
      session[:current_organization_id] = membership.organization_id
      session.delete(:organization_selection_required)
    end

    def organization_params
      params.require(:organization).permit(
        :name, :legal_name, :trade_name, :cnpj, :email, :phone,
        :zip_code, :street, :number, :complement, :district, :city, :state, :country,
        :kind, :responsible_email
      )
    end
  end
end
