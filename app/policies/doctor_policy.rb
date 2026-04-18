class DoctorPolicy < ApplicationPolicy
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

      scope.where(id: actor_doctor_id)
    end

    private

    def actor_doctor_id
      return user.id if user.is_a?(Doctor)
      return user.doctor_id if user.respond_to?(:doctor_id)

      nil
    end
  end

  private

  def own_profile?
    user.present? && record.id == actor_doctor_id
  end

  def actor_doctor_id
    return user.id if user.is_a?(Doctor)
    return user.doctor_id if user.respond_to?(:doctor_id)

    nil
  end
end
