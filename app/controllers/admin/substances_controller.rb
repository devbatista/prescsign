module Admin
  # Cadastro de substâncias ativas e sua classificação de controle (Portaria
  # 344/98 / tipo SNCR) no back-office. É a fonte de verdade que decide se um
  # medicamento exige receituário controlado. Escrita restrita a admin (support
  # lê — ver require_platform_writer!).
  class SubstancesController < Admin::BaseController
    before_action :set_substance, only: %i[show edit update activate deactivate]
    before_action :require_platform_writer!, only: %i[new create edit update activate deactivate]

    def index
      scope = apply_filters(Substance.ordered)
      @substances, @page, @total_pages, @total = paginate(scope)
    end

    def show
    end

    def new
      @substance = Substance.new(active: true)
    end

    def create
      @substance = Substance.new(substance_params)

      if @substance.save
        redirect_to admin_substance_path(@substance), notice: "Substância cadastrada."
      else
        flash.now[:alert] = @substance.errors.full_messages.to_sentence.presence || "Não foi possível cadastrar a substância."
        render :new, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @substance.update(substance_params)
        redirect_to admin_substance_path(@substance), notice: "Substância atualizada."
      else
        flash.now[:alert] = @substance.errors.full_messages.to_sentence.presence || "Não foi possível atualizar a substância."
        render :edit, status: :unprocessable_entity
      end
    end

    def activate
      @substance.update!(active: true)
      redirect_to admin_substance_path(@substance), notice: "Substância ativada."
    end

    def deactivate
      @substance.update!(active: false)
      redirect_to admin_substance_path(@substance), notice: "Substância desativada."
    end

    private

    def set_substance
      @substance = Substance.find(params[:id])
    end

    def substance_params
      params.require(:substance).permit(:name, :list_344, :sncr_type, :active)
    end

    def apply_filters(scope)
      @query = params[:q].to_s.strip
      @status = params[:status].to_s.strip
      @sncr_type = params[:sncr_type].to_s.strip

      if @query.present?
        term = "%#{@query.downcase}%"
        scope = scope.where("LOWER(name) LIKE :t OR LOWER(COALESCE(list_344, '')) LIKE :t", t: term)
      end

      scope = scope.where(active: true) if @status == "active"
      scope = scope.where(active: false) if @status == "inactive"
      scope = scope.where(sncr_type: @sncr_type) if Prescription::SNCR_TYPES.include?(@sncr_type)
      scope = scope.controlled if @sncr_type == "controlled"
      scope = scope.where(sncr_type: nil) if @sncr_type == "common"
      scope
    end
  end
end
