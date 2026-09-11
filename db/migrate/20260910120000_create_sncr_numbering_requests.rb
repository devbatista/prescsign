class CreateSncrNumberingRequests < ActiveRecord::Migration[8.1]
  SNCR_TYPES = %w[NRA NRB NRB2 NRR NRT RCE RET].freeze
  ENDPOINTS = %w[notificacao especial_retencao].freeze
  STATUSES = %w[pending succeeded failed unknown].freeze
  ORIGINS = %w[manual on_demand auto_refill].freeze

  def change
    create_table :sncr_numbering_requests, id: :uuid do |t|
      t.uuid :doctor_profile_id, null: false
      t.uuid :user_id
      t.string :sncr_type, null: false
      t.string :endpoint, null: false
      t.string :origin, null: false, default: "manual"
      t.string :status, null: false, default: "pending"
      t.integer :requested_quantity, null: false
      t.integer :imported_count
      t.integer :remote_balance
      t.string :remote_message
      t.string :range_start
      t.string :range_end
      t.string :error_message
      # Snapshot da inscricao no conselho no momento da solicitacao: o limite da
      # Anvisa e por inscricao, e o cadastro do medico pode mudar depois.
      t.string :council, null: false
      t.string :license_number, null: false
      t.string :license_state, null: false
      t.datetime :requested_at, null: false
      t.datetime :completed_at

      t.timestamps
    end

    # Cota diaria da notificacao: por medico + tipo + janela.
    add_index :sncr_numbering_requests, [ :doctor_profile_id, :sncr_type, :requested_at ],
              name: "index_sncr_numbering_requests_on_owner_type_requested_at"
    # Cota mensal do especial/retencao: o limite e do par RCE+RET, entao a chave
    # e o endpoint, nao o tipo.
    add_index :sncr_numbering_requests, [ :doctor_profile_id, :endpoint, :requested_at ],
              name: "index_sncr_numbering_requests_on_owner_endpoint_requested_at"
    add_index :sncr_numbering_requests, [ :doctor_profile_id, :status ],
              where: "status = 'pending'",
              name: "index_sncr_numbering_requests_pending"
    add_index :sncr_numbering_requests, :user_id,
              name: "index_sncr_numbering_requests_on_user_id"

    add_foreign_key :sncr_numbering_requests, :doctor_profiles, on_delete: :cascade
    add_foreign_key :sncr_numbering_requests, :users, on_delete: :nullify

    add_check_constraint :sncr_numbering_requests,
                         "sncr_type = ANY (ARRAY[#{SNCR_TYPES.map { |t| "'#{t}'" }.join(', ')}])",
                         name: "chk_sncr_numbering_requests_type_values"
    add_check_constraint :sncr_numbering_requests,
                         "endpoint = ANY (ARRAY[#{ENDPOINTS.map { |e| "'#{e}'" }.join(', ')}])",
                         name: "chk_sncr_numbering_requests_endpoint_values"
    add_check_constraint :sncr_numbering_requests,
                         "status = ANY (ARRAY[#{STATUSES.map { |s| "'#{s}'" }.join(', ')}])",
                         name: "chk_sncr_numbering_requests_status_values"
    add_check_constraint :sncr_numbering_requests,
                         "origin = ANY (ARRAY[#{ORIGINS.map { |o| "'#{o}'" }.join(', ')}])",
                         name: "chk_sncr_numbering_requests_origin_values"
    add_check_constraint :sncr_numbering_requests,
                         "requested_quantity > 0",
                         name: "chk_sncr_numbering_requests_quantity_positive"
    # Coerencia do ciclo de vida: pendente <=> sem desfecho; concluido <=> com
    # desfecho. `succeeded` exige imported_count; `failed`/`unknown` nao, porque
    # neles pode nao ter entrado numero nenhum.
    add_check_constraint :sncr_numbering_requests,
                         "(status = 'pending' AND completed_at IS NULL AND imported_count IS NULL) " \
                         "OR (status = 'succeeded' AND completed_at IS NOT NULL AND imported_count IS NOT NULL) " \
                         "OR (status IN ('failed', 'unknown') AND completed_at IS NOT NULL)",
                         name: "chk_sncr_numbering_requests_lifecycle_consistency"
  end
end
