class MedicalCertificatePolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    (same_organization_record? && (owner_record? || organization_admin?)) || admin?
  end

  def pdf?
    show?
  end

  def create?
    user.present?
  end

  def update?
    ((same_organization_record? && (owner_record? || organization_admin?)) || admin?) && !signed?
  end

  def destroy?
    ((same_organization_record? && (owner_record? || organization_admin?)) || admin?) && !signed?
  end

  def revoke?
    (same_organization_record? && (owner_record? || organization_admin?)) || admin?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.respond_to?(:admin?) && user.admin?

      tenant_scope = scope.where(organization_id: current_organization_id)
      return tenant_scope if user.organization_admin?(current_organization_id)

      tenant_scope.where(doctor_id: user.id)
    end

    private

    def current_organization_id
      Current.organization&.id || user.current_organization_id
    end
  end

  private

  def signed?
    record.status.to_s == "signed"
  end
end
