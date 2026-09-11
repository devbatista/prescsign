module Sncr
  # Solicita um lote de numeração ao SNCR e importa o resultado para o pool do
  # prescritor (SncrNumbering). Escolhe o endpoint pelo tipo de receita:
  # NRA/NRB/NRB2/NRR/NRT vão por Notificação de Receita (lista);
  # RCE/RET vão por Controle Especial/Retenção (bloco contínuo de 1.000).
  #
  # **A reserva commita antes da chamada HTTP.** A linha `pending` de
  # SncrNumberingRequest é durável antes de tocarmos a Anvisa, e só então vira
  # `succeeded`, `failed` ou `unknown`. Se o processo morrer no meio, a cota
  # fica bloqueada em vez de sumir — que é o comportamento certo para um limite
  # irreversível até o mês virar.
  #
  # Retorna o SncrNumberingRequest, que carrega quantos números entraram, o
  # saldo remoto e o aviso da Anvisa.
  class NumberingBatch
    NOTIFICACAO_TYPES = %w[NRA NRB NRB2 NRR NRT].freeze
    ESPECIAL_TYPES = %w[RCE RET].freeze

    def self.request!(...)
      new(...).request!
    end

    def initialize(doctor_profile:, sncr_type:, origin: "manual", user: nil,
                   access_token: nil, client: nil)
      @doctor_profile = doctor_profile
      @sncr_type = sncr_type.to_s
      @origin = origin.to_s
      @user = user
      @client = client || ClientFactory.build(access_token: access_token)
    end

    def request!
      raise Sncr::Error, "Tipo de receita inválido: #{@sncr_type}" unless valid_type?

      request = reserve!
      call_and_complete!(request)
      request
    end

    private

    def valid_type?
      ::Prescription::SNCR_TYPES.include?(@sncr_type)
    end

    def notificacao?
      NOTIFICACAO_TYPES.include?(@sncr_type)
    end

    # T1: trava o prescritor, confere a cota e grava a reserva. O lock serializa
    # duplo-clique e jobs concorrentes — sem ele, duas requisições simultâneas
    # leriam a mesma cota e ambas passariam.
    def reserve!
      ::SncrNumberingRequest.transaction do
        @doctor_profile.lock!

        quota = NumberingQuota.for(@doctor_profile)
        quota.ensure!(@sncr_type, origin: @origin)

        ::SncrNumberingRequest.create!(
          doctor_profile: @doctor_profile,
          user: @user,
          sncr_type: @sncr_type,
          endpoint: ::SncrNumberingRequest.endpoint_for(@sncr_type),
          origin: @origin,
          status: "pending",
          requested_quantity: quota.next_quantity_for(@sncr_type),
          council: conselho,
          license_number: documento,
          license_state: @doctor_profile.license_state,
          requested_at: Time.current
        )
      end
    end

    def call_and_complete!(request)
      notificacao? ? import_notificacao!(request) : import_especial_retencao!(request)
    rescue Sncr::TransportError => e
      # Sem resposta: pode ter sido processado do outro lado. Contar como gasto
      # e nunca reenviar sozinho — um retry aqui queima a segunda das 3
      # solicitações mensais de RCE/RET sem ninguém saber.
      fail_request!(request, e, status: "unknown")
      raise
    rescue Sncr::Error => e
      fail_request!(request, e, status: e.http_status.to_i >= 500 ? "unknown" : "failed")
      raise
    rescue StandardError => e
      fail_request!(request, e, status: "unknown")
      raise
    end

    def import_notificacao!(request)
      result = @client.request_notificacao!(
        receita: @sncr_type,
        conselho: conselho,
        uf: @doctor_profile.license_state,
        documento: documento,
        quantidade: request.requested_quantity
      )

      ::SncrNumberingRequest.transaction do
        imported = ::SncrNumbering.import_numbers!(
          doctor_profile: @doctor_profile,
          sncr_type: @sncr_type,
          numbers: result.numbers,
          sncr_numbering_request: request
        )
        request.update!(
          status: "succeeded",
          imported_count: imported,
          remote_balance: result.balance,
          remote_message: result.message,
          completed_at: Time.current
        )
      end
    end

    def import_especial_retencao!(request)
      result = @client.request_especial_retencao!(
        conselho: conselho,
        tipo: @sncr_type,
        documento: documento,
        uf: @doctor_profile.license_state,
        cnpj: platform_cnpj
      )

      ::SncrNumberingRequest.transaction do
        imported = ::SncrNumbering.import_range!(
          doctor_profile: @doctor_profile,
          sncr_type: @sncr_type,
          first: result.range_start,
          last: result.range_end,
          sncr_numbering_request: request
        )
        request.update!(
          status: "succeeded",
          imported_count: imported,
          remote_message: result.message,
          range_start: result.range_start,
          range_end: result.range_end,
          completed_at: Time.current
        )
      end
    end

    def fail_request!(request, error, status:)
      request.update!(
        status: status,
        error_message: error.message.to_s.truncate(500),
        completed_at: Time.current
      )
    rescue StandardError
      # Nunca mascarar o erro original da integração.
      nil
    end

    # Simplificação: assume CRM, pois o DoctorProfile ainda não separa conselho do
    # número (license_number). A refinar com um campo próprio (CRM/CRMV/CRO) —
    # até lá, fica gravado na requisição para dar rastro.
    def conselho
      "CRM"
    end

    def documento
      @doctor_profile.license_number
    end

    def platform_cnpj
      Rails.application.config.x.sncr.platform_cnpj
    end
  end
end
