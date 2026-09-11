module Sncr
  # Cota da Anvisa para solicitação de numeração. Read model puro: não faz I/O
  # externo, só lê o banco.
  #
  # Usado em três lugares com papéis diferentes — o gate do NumberingBatch, que
  # é a autoridade; o painel, que exibe e desabilita o botão; e o AutoRefill,
  # que decide se vale gastar. Checar em três, aplicar em um: se a regra vivesse
  # no controller, o job passaria por baixo.
  #
  # Limites, do §4.3 e §4.4 de docs/sncr/SNCR_INTEGRATION.md:
  #   - notificação (NRA/NRB/NRB2/NRR/NRT): 50 números por tipo, por prescritor,
  #     por dia; mínimo de 10 por requisição;
  #   - especial/retenção (RCE/RET): 3 requisições por mês por inscrição e
  #     3.000 números por mês, ambos somando RCE + RET.
  class NumberingQuota
    # A Anvisa vira o dia e o mês no horário de Brasília; o app roda em UTC
    # (config/application.rb). Usar Time.current.all_month aqui abriria três
    # horas por mês em que a nossa conta e a dela discordam — justamente na
    # fronteira onde o erro é irreversível até o mês seguinte.
    ZONE = ActiveSupport::TimeZone["America/Sao_Paulo"]

    NOTIFICACAO_DAILY_LIMIT = 50
    NOTIFICACAO_MIN_QUANTITY = 10
    ESPECIAL_MONTHLY_REQUEST_LIMIT = 3
    ESPECIAL_MONTHLY_NUMBER_LIMIT = 3_000
    ESPECIAL_BLOCK_SIZE = 1_000

    # O reabastecimento automático para na 2ª das 3 solicitações mensais. A
    # última fica para o médico gastar no dia em que precisar e não tiver a quem
    # recorrer até virar o mês — é o "reservando margem para picos" da §6.1.
    ESPECIAL_AUTO_REFILL_REQUEST_LIMIT = 2

    def self.for(doctor_profile, now: Time.current)
      new(doctor_profile, now: now)
    end

    def initialize(doctor_profile, now: Time.current)
      @doctor_profile = doctor_profile
      @now = now
    end

    def allows?(sncr_type, origin: "manual")
      block_reason(sncr_type, origin: origin).nil?
    end

    def ensure!(sncr_type, origin: "manual")
      reason = block_reason(sncr_type, origin: origin)
      raise Sncr::QuotaExceeded, reason if reason

      true
    end

    # Motivo do bloqueio, escrito para o médico ler na tela. nil quando permitido.
    def block_reason(sncr_type, origin: "manual")
      sncr_type = sncr_type.to_s
      especial?(sncr_type) ? especial_block_reason(sncr_type, origin) : notificacao_block_reason(sncr_type)
    end

    # Quantos números pedir agora. Na notificação é o que resta da cota do dia,
    # não os 50 fixos de antes: com 50 fixo, qualquer segunda solicitação no
    # mesmo dia era recusada pela Anvisa com erro opaco.
    def next_quantity_for(sncr_type)
      return ESPECIAL_BLOCK_SIZE if especial?(sncr_type.to_s)

      (NOTIFICACAO_DAILY_LIMIT - notificacao_used_today(sncr_type)).clamp(0, NOTIFICACAO_DAILY_LIMIT)
    end

    def notificacao_used_today(sncr_type)
      weigh(quota_scope.of_type(sncr_type.to_s).requested_between(day_start, day_end))
    end

    def especial_requests_this_month
      especial_month_scope.count
    end

    def especial_numbers_this_month
      weigh(especial_month_scope)
    end

    # Último saldo que a Anvisa reportou para o tipo, e quando. Só a notificação
    # devolve saldoReceitas; no especial/retenção volta nil.
    def remote_balance(sncr_type)
      last_succeeded(sncr_type)&.then { |r| [ r.remote_balance, r.completed_at ] }
    end

    def remote_message(sncr_type)
      last_succeeded(sncr_type)&.remote_message
    end

    def last_succeeded(sncr_type)
      SncrNumberingRequest
        .for_doctor(@doctor_profile)
        .of_type(sncr_type.to_s)
        .succeeded
        .order(requested_at: :desc)
        .first
    end

    private

    def especial?(sncr_type)
      NumberingBatch::ESPECIAL_TYPES.include?(sncr_type)
    end

    def notificacao_block_reason(sncr_type)
      used = notificacao_used_today(sncr_type)
      remaining = NOTIFICACAO_DAILY_LIMIT - used

      if remaining <= 0
        "Você já obteve as #{NOTIFICACAO_DAILY_LIMIT} numerações de #{sncr_type} permitidas hoje. " \
        "A cota da Anvisa é diária — tente novamente amanhã."
      elsif remaining < NOTIFICACAO_MIN_QUANTITY
        "Restam apenas #{remaining} numerações de #{sncr_type} na cota de hoje, " \
        "e a Anvisa exige no mínimo #{NOTIFICACAO_MIN_QUANTITY} por solicitação."
      end
    end

    def especial_block_reason(sncr_type, origin)
      requests = especial_requests_this_month

      if origin.to_s == "auto_refill" && requests >= ESPECIAL_AUTO_REFILL_REQUEST_LIMIT
        # Decisão interna, não recado de tela: o médico continua podendo pedir
        # manualmente a última do mês.
        return "Reabastecimento automático de #{sncr_type} pausado: " \
               "#{requests} de #{ESPECIAL_MONTHLY_REQUEST_LIMIT} solicitações mensais já usadas."
      end

      if requests >= ESPECIAL_MONTHLY_REQUEST_LIMIT
        "Você já usou as #{ESPECIAL_MONTHLY_REQUEST_LIMIT} solicitações de RCE/RET deste mês. " \
        "A cota da Anvisa é mensal por inscrição."
      elsif especial_numbers_this_month + ESPECIAL_BLOCK_SIZE > ESPECIAL_MONTHLY_NUMBER_LIMIT
        "O limite de #{ESPECIAL_MONTHLY_NUMBER_LIMIT} numerações RCE/RET no mês seria ultrapassado."
      end
    end

    # Peso da cota em SQL: o que a Anvisa entregou quando sabemos, o que pedimos
    # quando ainda não sabemos (pendente ou desfecho desconhecido). Espelha
    # SncrNumberingRequest#quota_weight, sem carregar os registros.
    def weigh(scope)
      scope.sum("COALESCE(imported_count, requested_quantity)").to_i
    end

    def quota_scope
      SncrNumberingRequest.for_doctor(@doctor_profile).counts_against_quota
    end

    def especial_month_scope
      quota_scope
        .of_endpoint("especial_retencao")
        .requested_between(month_start, month_end)
    end

    def zoned_now
      @zoned_now ||= @now.in_time_zone(ZONE)
    end

    def day_start = zoned_now.beginning_of_day
    def day_end   = zoned_now.end_of_day
    def month_start = zoned_now.beginning_of_month
    def month_end   = zoned_now.end_of_month
  end
end
