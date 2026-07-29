module Admin
  # Base for the platform back-office (admin.prescsign.local). Cross-organization;
  # restricted to platform admins (super_admin / admin / support). Does not require
  # an active organization context.
  class BaseController < ApplicationController
    layout "admin"

    before_action :require_platform_admin!

    private

    def require_platform_admin!
      return if current_user.admin? || current_user.support?

      redirect_to app_root_url(subdomain: "app"), allow_other_host: true,
        alert: "Acesso restrito ao back-office da plataforma."
    end

    # Escrita no back-office (ativar/desativar, alterar papéis) é só para
    # admin/super_admin; support tem acesso de leitura.
    def require_platform_writer!
      render_forbidden unless current_user.admin?
    end
  end
end
