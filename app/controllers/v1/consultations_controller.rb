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

      if @consultation.update(consultation_update_params)
        render_success(data: consultation_payload(@consultation))
      else
        render_error(@consultation.errors.full_messages, status: :unprocessable_content)
      end
    end

    def cancel
      authorize @consultation, :update?

      attributes = { status: "cancelled" }
      attributes[:finished_at] = Time.current if @consultation.finished_at.blank?

      if @consultation.update(attributes)
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
  end
end
