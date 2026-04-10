class DocumentPolicy < ApplicationPolicy
  MUTABLE_STATUSES = %w[issued].freeze

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
    (owner_record? || admin?) && mutable?
  end

  def destroy?
    (owner_record? || admin?) && mutable?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.respond_to?(:admin?) && user.admin?

      scope.where(doctor_id: user.id)
    end
  end

  private

  def mutable?
    MUTABLE_STATUSES.include?(record.status.to_s)
  end
end
