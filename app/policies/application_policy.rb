class ApplicationPolicy
  attr_reader :user, :record

  def initialize(user, record)
    @user = user
    @record = record
  end

  def index?
    false
  end

  def show?
    false
  end

  def create?
    false
  end

  def new?
    create?
  end

  def update?
    false
  end

  def edit?
    update?
  end

  def destroy?
    false
  end

  class Scope
    attr_reader :user, :scope

    def initialize(user, scope)
      @user = user
      @scope = scope
    end

    def resolve
      scope.none
    end

    private

    def support?
      user.respond_to?(:support?) && user.support?
    end
  end

  private

  def owner_record?
    return false unless user.present?
    return record.user_id == user.id if record.respond_to?(:user_id)
    return false unless record.respond_to?(:doctor_id)

    record.doctor_id == actor_doctor_id
  end

  def same_organization_record?
    return false unless user.present? && current_organization_id.present?
    return false unless record.respond_to?(:organization_id)

    record.organization_id == current_organization_id
  end

  def organization_admin?
    user.respond_to?(:organization_admin?) && user.organization_admin?(current_organization_id)
  end

  def organization_member?
    user.respond_to?(:membership_for) && user.membership_for(current_organization_id).present?
  end

  def current_organization_id
    Current.organization&.id || user&.current_organization_id
  end

  def actor_doctor_id
    return user.id if user.is_a?(Doctor)
    return user.doctor_id if user.respond_to?(:doctor_id)

    nil
  end

  def admin?
    user.respond_to?(:admin?) && user.admin?
  end

  def support?
    user.respond_to?(:support?) && user.support?
  end
end
