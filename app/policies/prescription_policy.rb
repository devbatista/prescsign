class PrescriptionPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    (same_organization_record? && (owner_record? || organization_admin? || support?)) || admin?
  end

  def pdf?
    show?
  end

  def create?
    user.present? && !support?
  end

  def update?
    return false if support?

    ((same_organization_record? && (owner_record? || organization_admin?)) || admin?) && !signed?
  end

  def destroy?
    return false if support?

    ((same_organization_record? && (owner_record? || organization_admin?)) || admin?) && !signed?
  end

  def revoke?
    return false if support?

    (same_organization_record? && (owner_record? || organization_admin?)) || admin?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.respond_to?(:admin?) && user.admin?

      tenant_scope = scope.where(organization_id: current_organization_id)
      return tenant_scope if user.organization_admin?(current_organization_id) || support?

      tenant_scope.where(user_id: actor_user_id)
    end

    private

    def current_organization_id
      Current.organization&.id || user.current_organization_id
    end

    def actor_doctor_id
      return user.id if user.is_a?(Doctor)
      return user.doctor_id if user.respond_to?(:doctor_id)

      nil
    end

    def actor_user_id
      return user.id if user.is_a?(User)
      return user.user&.id if user.is_a?(Doctor)
      return user.id if user.respond_to?(:id) && user.respond_to?(:has_role?)

      nil
    end
  end

  private

  def signed?
    record.status.to_s == "signed"
  end
end
