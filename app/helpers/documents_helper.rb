module DocumentsHelper
  DOCUMENT_STATUS_LABELS = {
    "issued" => "Emitido",
    "sent" => "Assinado/Enviado",
    "viewed" => "Visualizado",
    "revoked" => "Revogado",
    "expired" => "Expirado"
  }.freeze

  DOCUMENTABLE_STATUS_LABELS = {
    "draft" => "Rascunho",
    "signed" => "Assinado",
    "cancelled" => "Cancelado"
  }.freeze

  KIND_LABELS = {
    "prescription" => "Receita",
    "medical_certificate" => "Atestado"
  }.freeze

  DOCUMENT_STATUS_CLASSES = {
    "issued" => "bg-ps-info-bg text-ps-blue-700",
    "sent" => "bg-ps-success-bg text-ps-success-fg",
    "viewed" => "bg-ps-success-bg text-ps-success-fg",
    "revoked" => "bg-ps-error-bg text-ps-error-fg",
    "expired" => "bg-gray-100 text-ps-slate-500"
  }.freeze

  def document_kind_label(kind)
    KIND_LABELS.fetch(kind.to_s, kind.to_s.titleize)
  end

  def document_status_label(status)
    DOCUMENT_STATUS_LABELS.fetch(status.to_s, status.to_s.titleize)
  end

  def documentable_status_label(status)
    DOCUMENTABLE_STATUS_LABELS.fetch(status.to_s, status.to_s.titleize)
  end

  def document_status_pill(status)
    classes = DOCUMENT_STATUS_CLASSES.fetch(status.to_s, "bg-gray-100 text-ps-slate-500")
    content_tag :span, document_status_label(status),
                class: "rounded-full px-2.5 py-0.5 text-xs font-semibold #{classes}"
  end

  # Edit/PDF routes depend on the concrete documentable type.
  def documentable_edit_path(documentable)
    documentable.is_a?(Prescription) ? edit_prescription_path(documentable) : edit_medical_certificate_path(documentable)
  end

  def documentable_pdf_path(documentable)
    documentable.is_a?(Prescription) ? pdf_prescription_path(documentable) : pdf_medical_certificate_path(documentable)
  end

  def documentable_revoke_path(documentable)
    documentable.is_a?(Prescription) ? revoke_prescription_path(documentable) : revoke_medical_certificate_path(documentable)
  end
end
