class AddRequestToSncrNumberings < ActiveRecord::Migration[8.1]
  def change
    # Fecha a rastreabilidade requisicao -> numero -> receita. Nulo no historico
    # ja existente, e nulificado se a requisicao for removida: o numero vale por
    # si, a origem e informacao acessoria.
    add_column :sncr_numberings, :sncr_numbering_request_id, :uuid

    add_index :sncr_numberings, :sncr_numbering_request_id,
              name: "index_sncr_numberings_on_request_id"

    add_foreign_key :sncr_numberings, :sncr_numbering_requests, on_delete: :nullify
  end
end
