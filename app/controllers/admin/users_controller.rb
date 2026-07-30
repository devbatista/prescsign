module Admin
  # Cross-organization user & role management. Lista usuários da plataforma,
  # mostra detalhes (papéis, vínculos, perfil médico) e gerencia papéis de
  # plataforma + status. Escrita restrita a admin (ver require_platform_writer!).
  #
  # Papéis geríveis pela UI: admin/support/manager. `super_admin` e `doctor` são
  # exibidos, mas não geríveis aqui (evita escalonamento; `doctor` é do onboarding
  # clínico).
  class UsersController < Admin::BaseController
    MANAGEABLE_ROLES = %w[admin support manager].freeze

    before_action :set_user, only: %i[show grant_role revoke_role block activate]
    before_action :require_platform_writer!, only: %i[grant_role revoke_role block activate]
    before_action :protect_self!, only: %i[grant_role revoke_role block activate]
    before_action :protect_super_admin!, only: %i[grant_role revoke_role block activate]

    def index
      scope = User.includes(:user_roles, :doctor_profile).order(:email)
      scope = apply_filters(scope)
      @users, @page, @total_pages, @total = paginate(scope)
    end

    def show
      @roles = @user.user_roles.active.order(:role).pluck(:role)
      @memberships = @user.organization_memberships
                          .joins(:organization).includes(:organization)
                          .order("organizations.name")
    end

    def grant_role
      role = params[:role].to_s
      return reject_unmanageable_role unless MANAGEABLE_ROLES.include?(role)

      user_role = @user.user_roles.find_or_initialize_by(role: role)
      user_role.status = "active"
      user_role.save!
      redirect_to admin_user_path(@user), notice: "Papel “#{role_label(role)}” concedido."
    end

    def revoke_role
      role = params[:role].to_s
      return reject_unmanageable_role unless MANAGEABLE_ROLES.include?(role)

      @user.user_roles.where(role: role).destroy_all
      redirect_to admin_user_path(@user), notice: "Papel “#{role_label(role)}” revogado."
    end

    def block
      @user.update!(status: "blocked")
      redirect_to admin_user_path(@user), notice: "Usuário bloqueado."
    end

    def activate
      @user.update!(status: "active")
      redirect_to admin_user_path(@user), notice: "Usuário ativado."
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    # Um admin não altera os próprios papéis/status (evita auto-lockout e confusão).
    def protect_self!
      return unless @user == current_user

      redirect_to admin_user_path(@user), alert: "Você não pode alterar seus próprios papéis ou status."
    end

    # Só um super admin gerencia outro super admin.
    def protect_super_admin!
      return unless @user.has_role?("super_admin") && !current_user.has_role?("super_admin")

      redirect_to admin_user_path(@user), alert: "Apenas um super admin pode gerenciar outro super admin."
    end

    def reject_unmanageable_role
      redirect_to admin_user_path(@user), alert: "Papel inválido ou não gerenciável por aqui."
    end

    def role_label(role)
      AdminHelper::ROLE_LABELS.fetch(role.to_s, role.to_s.humanize)
    end

    def apply_filters(scope)
      @query = params[:q].to_s.strip
      @role = params[:role].to_s.strip
      @status = params[:status].to_s.strip

      scope = scope.where("LOWER(email) LIKE ?", "%#{@query.downcase}%") if @query.present?
      scope = scope.where(status: @status) if User::STATUSES.include?(@status)
      if UserRole::ROLES.include?(@role)
        scope = scope.where(id: UserRole.active.where(role: @role).select(:user_id))
      end
      scope
    end
  end
end
