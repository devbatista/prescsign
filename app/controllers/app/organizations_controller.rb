module App
  # Organization context within the panel (app.prescsign.local). For now: switching
  # the active org. Listing/creation come in Fase 4. The JWT API keeps V1::OrganizationsController.
  class OrganizationsController < WebBaseController
    # POST /organizations/switch
    def switch
      membership = current_user.organization_memberships.active
                               .find_by(organization_id: params[:organization_id])

      if membership.nil?
        return redirect_back fallback_location: app_root_path, alert: "Organização indisponível."
      end

      current_user.update!(current_organization_id: membership.organization_id)
      session[:current_organization_id] = membership.organization_id

      redirect_back fallback_location: app_root_path,
        notice: "Organização ativa: #{membership.organization.name}."
    end
  end
end
