# Authenticated landing page, routed by persona (admin / organization_responsible / doctor).
class DashboardController < WebBaseController
  before_action :ensure_active_organization!

  def show
    @persona = current_persona
  end
end
