class AddSncrTypeToPrescriptionItems < ActiveRecord::Migration[7.1]
  def change
    # Snapshot do tipo SNCR herdado do medicamento no momento da emissão. Mantém a
    # classificação usada mesmo que o catálogo/substância mude depois. Itens em
    # texto livre (sem medicamento) ficam nulos.
    add_column :prescription_items, :sncr_type, :string

    add_check_constraint :prescription_items,
                         "sncr_type IS NULL OR sncr_type IN ('NRA','NRB','NRB2','NRR','NRT','RCE','RET')",
                         name: "chk_prescription_items_sncr_type_values"
  end
end
