module Sncr
  # Solicita um lote de numeração ao SNCR e importa o resultado para o pool do
  # prescritor (SncrNumbering). Escolhe o endpoint pelo tipo de receita:
  # NRA/NRB/NRB2/NRR/NRT vão por Notificação de Receita (lista de até 50);
  # RCE/RET vão por Controle Especial/Retenção (bloco contínuo de 1.000).
  #
  # Retorna a quantidade de numerações importadas. Erros da API sobem como
  # Sncr::Error para o chamador tratar.
  class NumberingBatch
    NOTIFICACAO_TYPES = %w[NRA NRB NRB2 NRR NRT].freeze
    ESPECIAL_TYPES = %w[RCE RET].freeze
    NOTIFICACAO_BATCH_SIZE = 50

    def self.request!(...)
      new(...).request!
    end

    def initialize(doctor_profile:, sncr_type:, access_token: nil, client: nil)
      @doctor_profile = doctor_profile
      @sncr_type = sncr_type.to_s
      @client = client || ClientFactory.build(access_token: access_token)
    end

    def request!
      raise Sncr::Error, "Tipo de receita inválido: #{@sncr_type}" unless valid_type?

      notificacao? ? import_notificacao! : import_especial_retencao!
    end

    private

    def valid_type?
      ::Prescription::SNCR_TYPES.include?(@sncr_type)
    end

    def notificacao?
      NOTIFICACAO_TYPES.include?(@sncr_type)
    end

    def import_notificacao!
      result = @client.request_notificacao!(
        receita: @sncr_type,
        conselho: conselho,
        uf: @doctor_profile.license_state,
        documento: documento,
        quantidade: NOTIFICACAO_BATCH_SIZE
      )
      ::SncrNumbering.import_numbers!(
        doctor_profile: @doctor_profile,
        sncr_type: @sncr_type,
        numbers: result.numbers
      )
    end

    def import_especial_retencao!
      result = @client.request_especial_retencao!(
        conselho: conselho,
        tipo: @sncr_type,
        documento: documento,
        uf: @doctor_profile.license_state,
        cnpj: platform_cnpj
      )
      ::SncrNumbering.import_range!(
        doctor_profile: @doctor_profile,
        sncr_type: @sncr_type,
        first: result.range_start,
        last: result.range_end
      )
    end

    # Simplificação: assume CRM, pois o DoctorProfile ainda não separa conselho do
    # número (license_number). A refinar com um campo próprio (CRM/CRMV/CRO).
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
