module SncrHelper
  # Cota consumida, no formato que cada endpoint da Anvisa cobra: a notificação
  # é diária e conta números; o especial/retenção é mensal e conta solicitações
  # (é o limite que dói, porque são só 3 e não voltam até o mês virar).
  def sncr_quota_summary(quota, sncr_type)
    if Sncr::NumberingBatch::ESPECIAL_TYPES.include?(sncr_type)
      requests = quota.especial_requests_this_month
      numbers = quota.especial_numbers_this_month
      "#{requests} de #{Sncr::NumberingQuota::ESPECIAL_MONTHLY_REQUEST_LIMIT} solicitações · " \
        "#{number_with_delimiter(numbers)} / #{number_with_delimiter(Sncr::NumberingQuota::ESPECIAL_MONTHLY_NUMBER_LIMIT)} números no mês"
    else
      used = quota.notificacao_used_today(sncr_type)
      "#{used} / #{Sncr::NumberingQuota::NOTIFICACAO_DAILY_LIMIT} hoje"
    end
  end

  # Saldo que a Anvisa reportou na última solicitação bem-sucedida. Só a
  # notificação devolve `saldoReceitas`; no especial/retenção não há o que mostrar.
  def sncr_remote_balance_summary(quota, sncr_type)
    return nil if Sncr::NumberingBatch::ESPECIAL_TYPES.include?(sncr_type)

    balance, reported_at = quota.remote_balance(sncr_type)
    return nil if balance.blank?

    "#{balance}#{reported_at ? " · há #{time_ago_in_words(reported_at)}" : ''}"
  end

  SNCR_REQUEST_STATUS_LABELS = {
    "pending" => "Em andamento",
    "succeeded" => "Concluída",
    "failed" => "Recusada",
    "unknown" => "Não confirmada"
  }.freeze

  SNCR_REQUEST_ORIGIN_LABELS = {
    "manual" => "Manual",
    "on_demand" => "Emissão",
    "auto_refill" => "Automático"
  }.freeze

  def sncr_request_status_label(request)
    SNCR_REQUEST_STATUS_LABELS.fetch(request.status, request.status)
  end

  def sncr_request_origin_label(request)
    SNCR_REQUEST_ORIGIN_LABELS.fetch(request.origin, request.origin)
  end

  def sncr_request_status_classes(request)
    case request.status
    when "succeeded" then "bg-ps-success-bg text-ps-success-fg"
    when "unknown" then "bg-ps-warning-bg text-ps-warning-fg"
    when "failed" then "bg-ps-error-bg text-ps-error-fg"
    else "bg-[#eef3fa] text-[#4a6b93]"
    end
  end
end
