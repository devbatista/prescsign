class DoctorProfilePolicy < ApplicationPolicy
  def show?
    own_profile?
  end

  def update?
    own_profile?
  end

  def destroy?
    own_profile?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.present?

      scope.where(user_id: user.id)
    end
  end

  private

  def own_profile?
    user.present? && record.user_id == user.id
  end
end
