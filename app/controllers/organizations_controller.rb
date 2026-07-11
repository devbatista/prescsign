# Web organization context (session layer). For now: switching the active org.
# Listing/creation screens come in Fase 4. The JWT API keeps V1::OrganizationsController.
class OrganizationsController < WebBaseController
  # POST /organizacoes/:organization_id/trocar
  def switch
    membership = current_user.organization_memberships.active
                             .find_by(organization_id: params[:organization_id])

    if membership.nil?
      return redirect_back fallback_location: root_path, alert: "Organização indisponível."
    end

    current_user.update!(current_organization_id: membership.organization_id)
    session[:current_organization_id] = membership.organization_id

    redirect_back fallback_location: root_path,
      notice: "Organização ativa: #{membership.organization.name}."
  end
end
