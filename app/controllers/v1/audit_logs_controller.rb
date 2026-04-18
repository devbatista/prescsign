module V1
  class AuditLogsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_tenant_context!

    def index
      authorize AuditLog

      if filter_params[:document_id].blank? && filter_params[:patient_id].blank?
        return render_error("At least one filter is required: document_id or patient_id", status: :unprocessable_content)
      end

      logs = apply_filters(policy_scope(AuditLog))
      ordered_logs, sort_meta = apply_standard_order(
        logs,
        allowed_sorts: {
          "occurred_at" => :occurred_at,
          "created_at" => :created_at
        },
        default_sort: :occurred_at,
        default_dir: :desc
      )
      records, total, page, per_page = paginate_scope(ordered_logs)

      render_success(
        data: records.map { |log| audit_log_payload(log) },
        meta: build_pagination_meta(total: total, page: page, per_page: per_page, extra: sort_meta)
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
