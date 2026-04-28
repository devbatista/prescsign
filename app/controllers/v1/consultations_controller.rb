module V1
  class ConsultationsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_tenant_context!
    before_action :set_consultation

    def show
      authorize @consultation
      render_success(data: consultation_payload(@consultation))
    end

    def update
      authorize @consultation
      before_data = auditable_snapshot(@consultation)

      if @consultation.update(consultation_update_params)
        log_consultation_updated!(@consultation, before_data: before_data, after_data: auditable_snapshot(@consultation))
        render_success(data: consultation_payload(@consultation))
      else
        render_error(@consultation.errors.full_messages, status: :unprocessable_content)
      end
    end

    def cancel
      authorize @consultation, :update?
      before_data = auditable_snapshot(@consultation)

      attributes = { status: "cancelled" }
      attributes[:finished_at] = Time.current if @consultation.finished_at.blank?

      if @consultation.update(attributes)
        after_data = auditable_snapshot(@consultation)
        log_consultation_updated!(@consultation, before_data: before_data, after_data: after_data)
        log_consultation_status_changed!(@consultation, from: before_data["status"], to: after_data["status"])
        render_success(data: consultation_payload(@consultation))
      else
        render_error(@consultation.errors.full_messages, status: :unprocessable_content)
      end
    end

    private

    def set_consultation
      @consultation = policy_scope(Consultation)
                      .includes(:patient, :organization, :user)
                      .find(params[:id])
    end

    def consultation_update_params
      params.fetch(:consultation, {}).permit(
        :scheduled_at,
        :finished_at,
        :status,
        :chief_complaint,
        :notes,
        :diagnosis,
        metadata: {}
      )
    end

    def consultation_payload(consultation)
      consultation.slice(
        :id,
        :organization_id,
        :patient_id,
        :user_id,
        :scheduled_at,
        :finished_at,
        :status,
        :chief_complaint,
        :notes,
        :diagnosis,
        :metadata,
        :created_at,
          :updated_at
        )
    end

    def auditable_snapshot(consultation)
      consultation.attributes.slice(
        "status",
        "scheduled_at",
        "finished_at",
        "chief_complaint",
        "notes",
        "diagnosis"
      )
    end

    def log_consultation_updated!(consultation, before_data:, after_data:)
      AuditLog.record!(
        actor: current_user,
        organization: consultation.organization,
        patient: consultation.patient,
        resource: consultation,
        action: "updated",
        occurred_at: Time.current,
        before_data: before_data,
        after_data: after_data,
        request_id: request.request_id,
        request_origin: request.base_url,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end

    def log_consultation_status_changed!(consultation, from:, to:)
      AuditLog.record!(
        actor: current_user,
        organization: consultation.organization,
        patient: consultation.patient,
        resource: consultation,
        action: "status_changed",
        occurred_at: Time.current,
        before_data: { status: from },
        after_data: { status: to },
        request_id: request.request_id,
        request_origin: request.base_url,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end
  end
end
