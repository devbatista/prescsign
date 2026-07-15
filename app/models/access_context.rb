# Computes the current user's persona and menu visibility for the web layer.
# Mirrors the Vue app's router/accessControl.js + accessPolicies.js. The real
# authorization is still enforced by Pundit policies on each action.
class AccessContext
  def initialize(user:, membership:)
    @user = user
    @membership = membership
  end

  # :admin | :organization_responsible | :doctor | :unknown
  def persona
    return :admin if global_admin_scope?
    return :organization_responsible if %w[owner admin].include?(membership_role)
    return :doctor if membership_role == "doctor"

    :unknown
  end

  # Menu/section visibility. Section keys map to nav items.
  def can?(section)
    case section.to_sym
    when :dashboard
      true
    when :patients
      persona.in?(%i[admin organization_responsible])
    when :consultations, :agenda
      persona.in?(%i[admin organization_responsible doctor])
    when :documents_issue, :documents_sign
      persona.in?(%i[doctor organization_responsible])
    when :audit_logs
      persona.in?(%i[admin organization_responsible]) && !manager_only?
    when :doctors
      persona.in?(%i[admin organization_responsible])
    when :organization_create
      @user.has_role?("admin") || @user.has_role?("super_admin")
    when :about
      persona == :admin && !manager_only?
    when :profile
      true
    else
      false
    end
  end

  private

  attr_reader :user, :membership

  def membership_role
    @membership&.role
  end

  def global_admin_scope?
    @user.admin? || @user.support? || @user.has_role?("manager") || @user.has_role?("super_admin")
  end

  def manager_only?
    @user.has_role?("manager") && !@user.admin? && !@user.support?
  end
end
