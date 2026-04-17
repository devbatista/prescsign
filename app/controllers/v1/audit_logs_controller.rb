module V1
  class AuditLogsController < ApplicationController
    before_action :authenticate_doctor!
    before_action :ensure_tenant_context!

    def index
      authorize AuditLog

      if filter_params[:document_id].blank? && filter_params[:patient_id].blank?
        return render_error("At least one filter is required: document_id or patient_id", status: :unprocessable_content)
      end

      logs = apply_filters(policy_scope(AuditLog))
      page = normalize_page(params[:page])
      per_page = normalize_per_page(params[:per_page])
      total = logs.count
      records = logs.order(occurred_at: :desc).offset((page - 1) * per_page).limit(per_page)

      render_success(
        data: records.map { |log| audit_log_payload(log) },
        meta: {
          page: page,
          per_page: per_page,
          total: total,
          total_pages: (total.to_f / per_page).ceil
        }
      )
    end

    private

    def filter_params
      params.permit(:document_id, :patient_id, :page, :per_page)
    end

    def apply_filters(scope)
      filtered = scope
      filtered = filtered.where(document_id: filter_params[:document_id]) if filter_params[:document_id].present?
      filtered = filtered.where(patient_id: filter_params[:patient_id]) if filter_params[:patient_id].present?
      filtered
    end

    def normalize_page(value)
      parsed = value.to_i
      parsed.positive? ? parsed : 1
    end

    def normalize_per_page(value)
      parsed = value.to_i
      return 20 if parsed <= 0

      [parsed, 100].min
    end

    def audit_log_payload(log)
      log.slice(
        :id,
        :organization_id,
        :unit_id,
        :actor_type,
        :actor_id,
        :patient_id,
        :document_id,
        :resource_type,
        :resource_id,
        :action,
        :before_data,
        :after_data,
        :request_id,
        :request_origin,
        :ip_address,
        :user_agent,
        :occurred_at,
        :created_at
      )
    end
  end
end
