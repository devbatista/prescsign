module Admin
  # Catálogo global de medicamentos no back-office. Lista/filtra todo o catálogo
  # (não é multi-tenant), cria, edita e ativa/desativa. Escrita restrita a admin
  # (support tem acesso de leitura — ver require_platform_writer!).
  class MedicationsController < Admin::BaseController
    before_action :set_medication, only: %i[show edit update activate deactivate]
    before_action :require_platform_writer!, only: %i[new create edit update activate deactivate]

    def index
      scope = apply_filters(Medication.ordered)
      @medications, @page, @total_pages, @total = paginate(scope)
    end

    def show
    end

    def new
      @medication = Medication.new(active: true)
    end

    def create
      @medication = Medication.new(medication_params)

      if @medication.save
        redirect_to admin_medication_path(@medication), notice: "Medicamento cadastrado."
      else
        flash.now[:alert] = @medication.errors.full_messages.to_sentence.presence || "Não foi possível cadastrar o medicamento."
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @medication.update(medication_params)
        redirect_to admin_medication_path(@medication), notice: "Medicamento atualizado."
      else
        flash.now[:alert] = @medication.errors.full_messages.to_sentence.presence || "Não foi possível atualizar o medicamento."
        render :edit, status: :unprocessable_entity
      end
    end

    def activate
      @medication.update!(active: true)
      redirect_to admin_medication_path(@medication), notice: "Medicamento ativado."
    end

    def deactivate
      @medication.update!(active: false)
      redirect_to admin_medication_path(@medication), notice: "Medicamento desativado."
    end

    private

    def set_medication
      @medication = Medication.find(params[:id])
    end

    def medication_params
      params.require(:medication).permit(
        :name, :active_ingredient, :strength, :pharmaceutical_form, :control_class,
        :anvisa_registration, :manufacturer, :ean, :presentation, :default_posology, :active
      )
    end

    def apply_filters(scope)
      @query = params[:q].to_s.strip
      @status = params[:status].to_s.strip
      @control_class = params[:control_class].to_s.strip

      if @query.present?
        term = "%#{@query.downcase}%"
        scope = scope.where(
          "LOWER(name) LIKE :t OR LOWER(COALESCE(active_ingredient, '')) LIKE :t OR COALESCE(ean, '') LIKE :t",
          t: term
        )
      end

      scope = scope.where(active: true) if @status == "active"
      scope = scope.where(active: false) if @status == "inactive"
      scope = scope.where(control_class: @control_class) if Medication::CONTROL_CLASSES.include?(@control_class)
      scope
    end
  end
end
