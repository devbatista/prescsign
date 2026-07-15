class PatientPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    (same_organization_record? && (owner_record? || doctor_consultation_record? || organization_admin? || support?)) || admin?
  end

  def create?
    return false if support?

    user.present? && (organization_admin? || admin?)
  end

  def update?
    return false if support?

    (same_organization_record? && (owner_record? || organization_admin?)) || admin?
  end

  def destroy?
    return false if support?

    (same_organization_record? && (owner_record? || organization_admin?)) || admin?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.respond_to?(:admin?) && user.admin?

      tenant_scope = scope.where(organization_id: current_organization_id)
      return tenant_scope if user.organization_admin?(current_organization_id) || support?
      return tenant_scope.where(id: doctor_consultation_patient_ids) if doctor?

      tenant_scope.where(user_id: actor_user_id)
    end

    private

    def current_organization_id
      Current.organization&.id || user.current_organization_id
    end

    def actor_user_id
      user&.id
    end

    def doctor?
      user.respond_to?(:has_role?) && user.has_role?("doctor")
    end

    def doctor_consultation_patient_ids
      Consultation.where(organization_id: current_organization_id, user_id: actor_user_id)
                  .select(:patient_id).distinct
    end
  end

  private

  def doctor_consultation_record?
    return false unless user.respond_to?(:has_role?) && user.has_role?("doctor")

    Consultation.exists?(
      organization_id: current_organization_id,
      patient_id: record.id,
      user_id: user.id
    )
  end
end
