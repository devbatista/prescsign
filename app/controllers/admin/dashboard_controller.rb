module Admin
  class DashboardController < Admin::BaseController
    def show
      @organizations_count = Organization.count
      @active_organizations_count = Organization.where(active: true).count
      @users_count = User.count
      @pending_invitations_count = OrganizationRegistrationInvitation.pending.count
    end
  end
end
