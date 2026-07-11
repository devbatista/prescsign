module App
  # Consultations within the panel (app.prescsign.local). Mirrors
  # V1::ConsultationsController and V1::Patients::ConsultationsController,
  # reusing ConsultationPolicy. Consultations belong to a patient; the index
  # requires a selected patient (via ?patient_id=). Includes audit logging.
  class ConsultationsController < WebBaseController
    before_action :ensure_active_organization!
    before_action :set_patients_for_select, only: %i[index new create]
    before_action :set_consultation, only: %i[show edit update cancel]

    def index
      authorize Consultation
      @patient = find_patient(params[:patient_id]) if params[:patient_id].present?

      if @patient
        scope = apply_filters(policy_scope(Consultation).where(patient_id: @patient.id))
                .includes(:patient, :user).recent_first
        @consultations, @page, @total_pages, @total = paginate(scope)
      else
        @consultations = []
      end
    end

    def show
      authorize @consultation
    end

    def new
      @patient = find_patient(params[:patient_id]) if params[:patient_id].present?
      @consultation = Consultation.new(patient: @patient)
      authorize @consultation
    end

    def create
      @patient = find_patient(consultation_params[:patient_id].presence || params[:patient_id])
      @consultation = Consultation.new(
        consultation_params.except(:patient_id).merge(
          patient: @patient, user: current_user, organization: current_organization
        )
      )
      authorize @consultation

      if @consultation.save
        log_consultation!(@consultation, action: "created", before_data: {}, after_data: snapshot(@consultation))
        redirect_to consultation_path(@consultation), notice: "Consulta agendada com sucesso."
      else
        flash.now[:alert] = @consultation.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @consultation
    end

    def update
      authorize @consultation
      before_data = snapshot(@consultation)

      if @consultation.update(consultation_params.except(:patient_id))
        log_consultation!(@consultation, action: "updated", before_data: before_data, after_data: snapshot(@consultation))
        redirect_to consultation_path(@consultation), notice: "Consulta atualizada."
      else
        flash.now[:alert] = @consultation.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def cancel
      authorize @consultation, :update?
      before_data = snapshot(@consultation)

      attributes = { status: "cancelled" }
      # Stamp a finish time when missing. For a future appointment, Time.current
      # would fall before scheduled_at (rejected by the model validation), so we
      # clamp to scheduled_at — cancelling an upcoming consultation must succeed.
      if @consultation.finished_at.blank?
        attributes[:finished_at] = [Time.current, @consultation.scheduled_at].compact.max
      end

      if @consultation.update(attributes)
        after_data = snapshot(@consultation)
        log_consultation!(@consultation, action: "updated", before_data: before_data, after_data: after_data)
        log_consultation!(@consultation, action: "status_changed",
                          before_data: { "status" => before_data["status"] },
                          after_data: { "status" => after_data["status"] })
        redirect_to consultation_path(@consultation), notice: "Consulta cancelada."
      else
        redirect_to consultation_path(@consultation), alert: @consultation.errors.full_messages.to_sentence
      end
    end

    private

    def set_consultation
      @consultation = policy_scope(Consultation).includes(:patient, :organization, :user).find(params[:id])
    end

    def set_patients_for_select
      @patients = policy_scope(Patient).where(active: true).order(:full_name)
    end

    def find_patient(id)
      policy_scope(Patient).find(id)
    end

    def consultation_params
      params.require(:consultation).permit(
        :patient_id, :scheduled_at, :finished_at, :status,
        :chief_complaint, :notes, :diagnosis
      )
    end

    def apply_filters(scope)
      scope = scope.with_status(params[:status]) if params[:status].present?
      scope.scheduled_between(parsed_time(params[:scheduled_from]), parsed_time(params[:scheduled_to]))
    end

    def parsed_time(value)
      return nil if value.blank?

      Time.zone.parse(value.to_s)
    rescue ArgumentError
      nil
    end

    def snapshot(consultation)
      consultation.attributes.slice("status", "scheduled_at", "finished_at", "chief_complaint", "notes", "diagnosis")
    end

    def log_consultation!(consultation, action:, before_data:, after_data:)
      AuditLog.record!(
        actor: current_user,
        organization: consultation.organization,
        patient: consultation.patient,
        resource: consultation,
        action: action,
        occurred_at: Time.current,
        before_data: before_data,
        after_data: after_data,
        request_id: request.request_id,
        request_origin: request.base_url,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end
  end
end
