module ConsultationsHelper
  CONSULTATION_STATUS_LABELS = {
    "scheduled" => "Agendada",
    "completed" => "Concluída",
    "cancelled" => "Cancelada"
  }.freeze

  CONSULTATION_STATUS_CLASSES = {
    "scheduled" => "bg-ps-info-bg text-ps-blue-700",
    "completed" => "bg-ps-success-bg text-ps-success-fg",
    "cancelled" => "bg-ps-error-bg text-ps-error-fg"
  }.freeze

  def consultation_status_label(status)
    CONSULTATION_STATUS_LABELS.fetch(status, status.to_s.titleize)
  end

  def consultation_status_options
    Consultation::STATUSES.map { |status| [consultation_status_label(status), status] }
  end

  def consultation_status_pill(status)
    classes = CONSULTATION_STATUS_CLASSES.fetch(status, "bg-gray-100 text-ps-slate-500")
    content_tag :span, consultation_status_label(status),
                class: "rounded-full px-2 py-0.5 text-xs font-medium #{classes}"
  end
end
