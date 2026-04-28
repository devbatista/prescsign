module V1
  module Patients
    class ConsultationsController < ApplicationController
      before_action :authenticate_user!
      before_action :ensure_tenant_context!
      before_action :set_patient

      def index
        authorize Consultation

        consultations = apply_filters(policy_scope(Consultation).where(patient_id: @patient.id))
        ordered_consultations, sort_meta = apply_standard_order(
          consultations,
          allowed_sorts: {
            "scheduled_at" => :scheduled_at,
            "created_at" => :created_at,
            "updated_at" => :updated_at
          },
          default_sort: :scheduled_at,
          default_dir: :desc
        )
        records, total, page, per_page = paginate_scope(ordered_consultations)

        render_success(
          data: records.map { |consultation| consultation_payload(consultation) },
          meta: build_pagination_meta(total: total, page: page, per_page: per_page, extra: sort_meta)
        )
      end

      def create
        consultation = Consultation.new(
          consultation_create_params.merge(
            patient: @patient,
            user: current_user,
            organization: current_organization
          )
        )
        authorize consultation

        if consultation.save
          log_consultation_created!(consultation)
          render_success(data: consultation_payload(consultation), status: :created)
        else
          render_error(consultation.errors.full_messages, status: :unprocessable_content)
        end
      end

      private

      def set_patient
        @patient = policy_scope(Patient).find(params[:patient_id])
        authorize @patient, :show?
      end

      def consultation_create_params
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

      def apply_filters(scope)
        filtered = scope
        filtered = filtered.with_status(filter_params[:status]) if filter_params[:status].present?
        filtered.scheduled_between(parsed_time(filter_params[:scheduled_from]), parsed_time(filter_params[:scheduled_to]))
      end

      def filter_params
        params.permit(:status, :scheduled_from, :scheduled_to, :sort_by, :sort_dir, :page, :per_page)
      end

      def parsed_time(value)
        return nil if value.blank?

        Time.zone.parse(value.to_s)
      rescue ArgumentError
        nil
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

      def log_consultation_created!(consultation)
        AuditLog.record!(
          actor: current_user,
          organization: consultation.organization,
          patient: consultation.patient,
          resource: consultation,
          action: "created",
          occurred_at: Time.current,
          before_data: {},
          after_data: consultation.attributes.slice(
            "status",
            "scheduled_at",
            "finished_at",
            "chief_complaint",
            "notes",
            "diagnosis"
          ),
          request_id: request.request_id,
          request_origin: request.base_url,
          ip_address: request.remote_ip,
          user_agent: request.user_agent
        )
      end
    end
  end
end
