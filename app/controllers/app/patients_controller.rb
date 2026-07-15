module App
  # Patient management within the panel (app.prescsign.local). Mirrors
  # V1::PatientsController, reusing PatientPolicy. Destroy is a soft-inactivate.
  class PatientsController < ApplicationController
    before_action :ensure_active_organization!
    before_action :set_patient, only: %i[show edit update destroy]

    def index
      authorize Patient
      scope = apply_search(policy_scope(Patient)).order(:full_name)
      @patients, @page, @total_pages, @total = paginate(scope)
    end

    def show
      authorize @patient
      @documents = @patient.documents.order(created_at: :desc)
      @consultations = policy_scope(Consultation).where(patient_id: @patient.id)
                                                 .includes(:specialty, user: :doctor_profile).recent_first.limit(10)
      @new_consultation = Consultation.new(patient: @patient)
      @organization_doctors = organization_doctors
      @specialties = available_specialties
    end

    def new
      @patient = current_user.patients.new
      authorize @patient
    end

    def create
      @patient = current_user.patients.new(patient_params.merge(organization: current_organization))
      authorize @patient

      if @patient.save
        redirect_to patient_path(@patient), notice: "Paciente cadastrado com sucesso."
      else
        flash.now[:alert] = @patient.errors.full_messages.to_sentence
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @patient
    end

    def update
      authorize @patient

      if @patient.update(patient_params)
        redirect_to patient_path(@patient), notice: "Paciente atualizado."
      else
        flash.now[:alert] = @patient.errors.full_messages.to_sentence
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      authorize @patient
      @patient.update!(active: false)
      redirect_to patients_path, notice: "Paciente inativado."
    end

    private

    def set_patient
      @patient = policy_scope(Patient).find(params[:id])
    end

    # Active doctors of the current organization, for the "Especialista" select
    # on the patient page (optional professional when scheduling a consultation).
    def organization_doctors
      user_ids = OrganizationMembership
                 .where(organization_id: current_organization.id, role: "doctor", status: "active")
                 .pluck(:user_id)
      DoctorProfile.where(user_id: user_ids, active: true).includes(:specialties).order(:full_name)
    end

    def available_specialties
      return organization_doctor_specialties unless current_persona == :doctor

      current_user.doctor_profile&.specialties&.active&.order(:name) || Specialty.none
    end

    def organization_doctor_specialties
      Specialty.active
               .joins(:doctor_profiles)
               .where(doctor_profiles: { id: organization_doctors.select(:id), active: true })
               .distinct
               .order(:name)
    end

    def patient_params
      params.require(:patient).permit(:full_name, :cpf, :birth_date, :email, :phone, :active)
    end

    def apply_search(scope)
      name = params[:name].to_s.strip
      document = params[:document].to_s.gsub(/\D/, "")

      scope = scope.where("lower(full_name) LIKE lower(?)", "%#{name}%") if name.present?
      scope = scope.where("cpf LIKE ?", "%#{document}%") if document.present?
      scope
    end
  end
end
