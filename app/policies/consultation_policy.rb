class ConsultationPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    (same_organization_record? && (organization_member? || support?)) || admin?
  end

  def create?
    return false unless user.present?
    return false if support?
    return true if admin?

    organization_member?
  end

  def update?
    return false unless user.present?
    return false if support?

    (same_organization_record? && organization_member?) || admin?
  end

  def destroy?
    return false unless user.present?
    return false if support?

    (same_organization_record? && organization_member?) || admin?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.respond_to?(:admin?) && user.admin?
      return scope.none if current_organization_id.blank?

      tenant_scope = scope.where(organization_id: current_organization_id)
      return tenant_scope if user.membership_for(current_organization_id).present? || support?

      scope.none
    end

    private

    def current_organization_id
      Current.organization&.id || user.current_organization_id
    end
  end
end
