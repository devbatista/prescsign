class AuditLogPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.respond_to?(:admin?) && user.admin?

      tenant_scope = scope.where(organization_id: current_organization_id)
      return tenant_scope if user.organization_admin?(current_organization_id) || support?

      owner_document_ids = Document.where(organization_id: current_organization_id, user_id: actor_user_id).select(:id)
      owner_patient_ids = Patient.where(organization_id: current_organization_id, user_id: actor_user_id).select(:id)
      scope_by_document = tenant_scope.where(document_id: owner_document_ids)
      scope_by_patient = tenant_scope.where(patient_id: owner_patient_ids)
      scope_by_actor = tenant_scope.where(actor_type: "User", actor_id: actor_user_id)

      scope_by_document.or(scope_by_patient).or(scope_by_actor).distinct
    end

    private

    def current_organization_id
      Current.organization&.id || user.current_organization_id
    end

    def actor_user_id
      user&.id
    end
  end
end
