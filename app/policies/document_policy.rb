class DocumentPolicy < ApplicationPolicy
  MUTABLE_STATUSES = %w[issued].freeze
  NON_RESENDABLE_STATUSES = %w[revoked expired].freeze

  def index?
    user.present?
  end

  def show?
    (same_organization_record? && (owner_record? || organization_admin? || support?)) || admin?
  end

  def create?
    user.present? && !support?
  end

  def update?
    return false if support?

    ((same_organization_record? && (owner_record? || organization_admin?)) || admin?) && mutable?
  end

  def destroy?
    return false if support?

    ((same_organization_record? && (owner_record? || organization_admin?)) || admin?) && mutable?
  end

  def sign?
    return false if support?

    ((same_organization_record? && (owner_record? || organization_admin?)) || admin?) && mutable?
  end

  def integrity_check?
    (same_organization_record? && (owner_record? || organization_admin? || support?)) || admin?
  end

  def resend?
    return false if support?

    ((same_organization_record? && (owner_record? || organization_admin?)) || admin?) && resendable?
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

    def actor_user_id
      user&.id
    end
  end

  private

  def mutable?
    MUTABLE_STATUSES.include?(record.status.to_s)
  end

  def resendable?
    !NON_RESENDABLE_STATUSES.include?(record.status.to_s)
  end
end
