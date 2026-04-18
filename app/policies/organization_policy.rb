class OrganizationPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    member_of_record? || admin? || support?
  end

  def switch?
    show?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.present?
      return scope.where(active: true) if (user.respond_to?(:admin?) && user.admin?) || (user.respond_to?(:support?) && user.support?)

      scope.joins(:organization_memberships)
           .merge(OrganizationMembership.active.where(user_id: actor_user_id))
           .where(active: true)
           .distinct
    end

    private

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

  def member_of_record?
    return false unless user.present?
    return false unless record.respond_to?(:id)

    user.membership_for(record.id).present?
  end
end
