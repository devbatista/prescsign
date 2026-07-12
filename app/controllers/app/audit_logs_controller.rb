module App
  # Audit trail within the panel (app.prescsign.local). Mirrors
  # V1::AuditLogsController, reusing AuditLogPolicy + Scope. Like the API, at
  # least one filter (patient or document) is required before listing.
  class AuditLogsController < ApplicationController
    before_action :ensure_active_organization!

    def index
      authorize AuditLog

      @patients = policy_scope(Patient).order(:full_name)
      @patient_id = params[:patient_id].presence
      @document_id = params[:document_id].presence
      @filtered = @patient_id.present? || @document_id.present?

      return unless @filtered

      scope = apply_filters(policy_scope(AuditLog))
              .includes(:actor, :patient, :document)
              .order(occurred_at: :desc)
      @logs, @page, @total_pages, @total = paginate(scope)
    end

    private

    def apply_filters(scope)
      scope = scope.where(patient_id: @patient_id) if @patient_id.present?
      scope = scope.where(document_id: @document_id) if @document_id.present?
      scope
    end
  end
end
