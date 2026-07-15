module App
  # Consultations within the panel (app.prescsign.local). Mirrors
  # V1::ConsultationsController and V1::Patients::ConsultationsController,
  # reusing ConsultationPolicy. Consultations belong to a patient and can be
  # filtered by ?patient_id=. Includes audit logging.
  class ConsultationsController < ApplicationController
    before_action :ensure_active_organization!
    before_action :set_patients_for_select, only: %i[index new create]
    before_action :set_specialties_for_select, only: %i[new create edit update]
    before_action :set_organization_doctors_for_select, only: %i[new create edit update]
    before_action :set_consultation, only: %i[show edit update cancel]

    def index
      authorize Consultation
      @patient = find_patient(params[:patient_id]) if params[:patient_id].present?

      scope = consultation_index_scope
      scope = scope.where(patient_id: @patient.id) if @patient
      scope = apply_filters(scope).includes(:patient, :specialty, user: :doctor_profile).recent_first
      @consultations, @page, @total_pages, @total = paginate(scope, per_page: 10)
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
      specialty = resolve_specialty(consultation_params[:specialty_id])
      @consultation = Consultation.new(
        consultation_attributes.merge(
          patient: @patient, specialty: specialty,
          user: resolve_professional(consultation_params[:user_id], specialty: specialty),
          organization: current_organization
        )
      )
      authorize @consultation

      if specialty.blank?
        @consultation.errors.add(:specialty, "deve ser informada")
      end

      if @consultation.errors.empty? && @consultation.save
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
      specialty = resolve_specialty(consultation_params[:specialty_id]) || @consultation.specialty
      attributes = consultation_attributes
      attributes[:specialty] = specialty if consultation_params.key?(:specialty_id)
      attributes[:user] = resolve_professional(consultation_params[:user_id], specialty: specialty) if consultation_params.key?(:user_id)

      if @consultation.update(attributes)
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
      @consultation = policy_scope(Consultation).includes(:patient, :organization, :specialty, user: :doctor_profile).find(params[:id])
    end

    def set_patients_for_select
      @patients = policy_scope(Patient).where(active: true).order(:full_name)
    end

    def set_specialties_for_select
      @specialties = available_specialties
    end

    def set_organization_doctors_for_select
      @organization_doctors = organization_doctors
    end

    def find_patient(id)
      policy_scope(Patient).find(id)
    end

    def consultation_index_scope
      scope = policy_scope(Consultation)
      return scope.where(user_id: current_user.id) if current_persona == :doctor

      scope
    end

    def consultation_params
      params.require(:consultation).permit(
        :patient_id, :user_id, :specialty_id, :scheduled_at, :finished_at, :status,
        :chief_complaint, :notes, :diagnosis
      )
    end

    def consultation_attributes
      consultation_params.except(:patient_id, :user_id, :specialty_id)
    end

    # Optional professional for the consultation. Doctors may only schedule for
    # themselves; organization managers can choose another active organization
    # professional.
    def resolve_professional(user_id, specialty:)
      return current_user if current_persona == :doctor
      return automatic_professional_for(specialty) if user_id.blank?

      member = OrganizationMembership.active.find_by(
        organization_id: current_organization.id,
        user_id: user_id,
        role: "doctor"
      )
      doctor = member&.user
      return nil if doctor.blank?
      return doctor if specialty.blank?
      return doctor if doctor.doctor_profile&.specialties&.exists?(id: specialty.id)

      nil
    end

    def automatic_professional_for(specialty)
      return nil if specialty.blank?

      organization_doctors
        .joins(:specialties)
        .where(specialties: { id: specialty.id })
        .first
        &.user
    end

    def resolve_specialty(specialty_id)
      return nil if specialty_id.blank?

      available_specialties.find_by(id: specialty_id)
    end

    def available_specialties
      return organization_doctor_specialties unless current_persona == :doctor

      current_user.doctor_profile&.specialties&.active&.order(:name) || Specialty.none
    end

    def organization_doctors
      user_ids = OrganizationMembership
                 .where(organization_id: current_organization.id, role: "doctor", status: "active")
                 .pluck(:user_id)
      DoctorProfile.where(user_id: user_ids, active: true).includes(:specialties).order(:full_name)
    end

    def organization_doctor_specialties
      Specialty.active
               .joins(:doctor_profiles)
               .where(doctor_profiles: { id: organization_doctors.select(:id), active: true })
               .distinct
               .order(:name)
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
      consultation.attributes.slice(
        "status", "scheduled_at", "finished_at", "chief_complaint", "notes",
        "diagnosis", "user_id", "specialty_id"
      )
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
