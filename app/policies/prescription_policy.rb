class PrescriptionPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    owner_record? || admin?
  end

  def create?
    user.present?
  end

  def update?
    (owner_record? || admin?) && !signed?
  end

  def destroy?
    (owner_record? || admin?) && !signed?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.respond_to?(:admin?) && user.admin?

      scope.where(doctor_id: user.id)
    end
  end

  private

  def signed?
    record.status.to_s == "signed"
  end
end
