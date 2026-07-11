module App
  # Patient management within the panel (app.prescsign.local). Mirrors
  # V1::PatientsController, reusing PatientPolicy. Destroy is a soft-inactivate.
  class PatientsController < WebBaseController
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
