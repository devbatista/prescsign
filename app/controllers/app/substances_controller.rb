module App
  # Busca na base de substâncias sujeitas a controle especial, para a
  # identificação assistida de item de receita digitado à mão.
  #
  # A base é exclusivamente a lista controlada — Anexos da Portaria 344/98 mais
  # os antimicrobianos e GLP-1 da IN 360/2025. Isso é o que dá sentido à busca:
  # **não encontrar já é a resposta "não é controlado"**, e por isso o médico
  # nunca precisa escolher o tipo de receituário. Ele identifica a substância; o
  # tipo sai de `Substance#sncr_type`.
  #
  # Ver docs/CLASSIFICACAO_CONTROLADA.md.
  class SubstancesController < ApplicationController
    before_action :ensure_active_organization!

    MIN_QUERY_LENGTH = 2
    RESULT_LIMIT = 20

    def search
      query = params[:q].to_s.squish

      return render json: { results: [] } if query.length < MIN_QUERY_LENGTH

      render json: { results: results_for(query).map { |substance| serialize(substance) } }
    end

    private

    def results_for(query)
      term = "%#{sanitize_like(query.downcase)}%"
      prefix = "#{sanitize_like(query.downcase)}%"

      Substance
        .active
        .where("LOWER(name) LIKE :term", term: term)
        # Quem começa com o que foi digitado vem antes de quem só contém.
        .order(Arel.sql(ActiveRecord::Base.sanitize_sql_array([ "(LOWER(name) LIKE ?) DESC", prefix ])))
        .order(:name)
        .limit(RESULT_LIMIT)
    end

    def sanitize_like(value)
      ActiveRecord::Base.sanitize_sql_like(value)
    end

    def serialize(substance)
      {
        id: substance.id,
        name: substance.name,
        list_344: substance.list_344,
        sncr_type: substance.sncr_type,
        sncr_type_label: Prescription::SNCR_TYPE_LABELS[substance.sncr_type]
      }
    end
  end
end
