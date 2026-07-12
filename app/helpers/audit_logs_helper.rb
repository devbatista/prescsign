module AuditLogsHelper
  AUDIT_ACTION_LABELS = {
    "created" => "Criado",
    "updated" => "Atualizado",
    "signed" => "Assinado",
    "sent" => "Enviado",
    "viewed" => "Visualizado",
    "revoked" => "Revogado",
    "status_changed" => "Status alterado"
  }.freeze

  AUDIT_ACTION_CLASSES = {
    "created" => "bg-ps-info-bg text-ps-blue-700",
    "updated" => "bg-ps-info-bg text-ps-blue-700",
    "signed" => "bg-ps-success-bg text-ps-success-fg",
    "sent" => "bg-ps-success-bg text-ps-success-fg",
    "viewed" => "bg-gray-100 text-ps-slate-600",
    "revoked" => "bg-ps-error-bg text-ps-error-fg",
    "status_changed" => "bg-gray-100 text-ps-slate-600"
  }.freeze

  RESOURCE_TYPE_LABELS = {
    "Consultation" => "Consulta",
    "Prescription" => "Receita",
    "MedicalCertificate" => "Atestado",
    "Document" => "Documento",
    "Patient" => "Paciente"
  }.freeze

  def audit_action_label(action)
    AUDIT_ACTION_LABELS.fetch(action.to_s, action.to_s.humanize)
  end

  def audit_action_pill(action)
    classes = AUDIT_ACTION_CLASSES.fetch(action.to_s, "bg-gray-100 text-ps-slate-500")
    content_tag :span, audit_action_label(action),
                class: "rounded-full px-2.5 py-0.5 text-xs font-semibold #{classes}"
  end

  def audit_resource_label(log)
    label = RESOURCE_TYPE_LABELS.fetch(log.resource_type.to_s, log.resource_type.to_s)
    "#{label} ##{log.resource_id.to_s.first(8)}"
  end

  def audit_actor_label(log)
    return log.actor.email if log.actor.respond_to?(:email) && log.actor.email.present?

    [log.actor_type, log.actor_id&.to_s&.first(8)].compact.join(" ").presence || "Sistema"
  end
end
