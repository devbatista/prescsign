module App
  # Busca no catálogo global de medicamentos, para o autocomplete da emissão de
  # receita (app.prescsign.local).
  #
  # Antes o formulário embutia o catálogo inteiro num `<datalist>`. Com o
  # catálogo da Anvisa carregado isso virou megabytes de HTML por render, e o
  # casamento pelo rótulo ("nome + concentração") era ambíguo: milhares de
  # apresentações compartilham rótulo, então o `medication_id` gravado — que é
  # quem decide o `sncr_type` do item — saía por sorteio entre fabricantes.
  # Aqui a busca é do servidor, limitada, e cada resultado devolve o que
  # distingue a apresentação (fabricante, apresentação, tarja, tipo SNCR).
  #
  # O catálogo não é multi-tenant: qualquer usuário autenticado com organização
  # ativa consulta a mesma lista, como já era com o datalist.
  class MedicationsController < ApplicationController
    before_action :ensure_active_organization!

    MIN_QUERY_LENGTH = 2
    RESULT_LIMIT = 20

    def search
      query = params[:q].to_s.squish

      return render json: { results: [] } if query.length < MIN_QUERY_LENGTH

      render json: { results: results_for(query).map { |medication| serialize(medication) } }
    end

    private

    def results_for(query)
      term = "%#{sanitize_like(query.downcase)}%"
      prefix = "#{sanitize_like(query.downcase)}%"

      Medication
        .active
        .includes(:substances)
        .where(
          "LOWER(name) LIKE :term OR LOWER(COALESCE(active_ingredient, '')) LIKE :term OR COALESCE(ean, '') LIKE :term",
          term: term
        )
        # Quem começa com o que foi digitado vem antes de quem só contém.
        .order(Arel.sql(ActiveRecord::Base.sanitize_sql_array([ "(LOWER(name) LIKE ?) DESC", prefix ])))
        .order(:name, :strength)
        .limit(RESULT_LIMIT)
    end

    def sanitize_like(value)
      ActiveRecord::Base.sanitize_sql_like(value)
    end

    def serialize(medication)
      {
        id: medication.id,
        name: medication.name,
        label: medication.label,
        strength: medication.strength,
        active_ingredient: medication.active_ingredient,
        presentation: medication.presentation,
        manufacturer: medication.manufacturer,
        posology: medication.default_posology,
        control_class: medication.control_class,
        sncr_type: medication.effective_sncr_type
      }
    end
  end
end
