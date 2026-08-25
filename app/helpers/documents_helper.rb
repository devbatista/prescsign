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

  DELIVERY_STATUS_LABELS = {
    "queued" => "Na fila",
    "processing" => "Processando",
    "sent" => "Enviado",
    "delivered" => "Entregue",
    "failed" => "Falhou"
  }.freeze

  DELIVERY_STATUS_CLASSES = {
    "delivered" => "bg-ps-success-bg text-ps-success-fg",
    "sent" => "bg-ps-info-bg text-ps-blue-700",
    "failed" => "bg-ps-error-bg text-ps-error-fg"
  }.freeze

  # Ícones em traço, no mesmo estilo do resto da interface.
  DELIVERY_CHANNEL_ICON_PATHS = {
    "email" => ["M3.25 5.75h13.5v8.5H3.25z", "m3.6 6.2 6.4 4.8 6.4-4.8"],
    "sms" => ["M6.75 3.25h6.5v13.5h-6.5z", "M9 14.75h2"],
    "whatsapp" => ["M10 3.75c-3.73 0-6.75 2.55-6.75 5.7 0 1.72.9 3.26 2.33 4.3l-.66 2.5 2.8-1.4c.72.19 1.49.3 2.28.3 3.73 0 6.75-2.55 6.75-5.7S13.73 3.75 10 3.75Z"]
  }.freeze

  def delivery_channel_label(channel)
    DeliveryLog::CHANNEL_LABELS.fetch(channel.to_s, channel.to_s.titleize)
  end

  def delivery_status_pill(status)
    classes = DELIVERY_STATUS_CLASSES.fetch(status.to_s, "bg-gray-100 text-ps-slate-500")
    content_tag :span, DELIVERY_STATUS_LABELS.fetch(status.to_s, status.to_s.titleize),
                class: "rounded-full px-2.5 py-0.5 text-xs font-semibold #{classes}"
  end

  def delivery_channel_icon(channel, css_class: "h-4 w-4")
    paths = DELIVERY_CHANNEL_ICON_PATHS.fetch(channel.to_s, DELIVERY_CHANNEL_ICON_PATHS["email"])
    tag.svg safe_join(paths.map { |d| tag.path(d: d) }),
            class: css_class, viewBox: "0 0 20 20", fill: "none", stroke: "currentColor",
            "stroke-width": "1.8", "stroke-linecap": "round", "stroke-linejoin": "round",
            "aria-hidden": "true"
  end

  # O destinatário é gravado como o médico digitou — um envio antigo pode ter
  # só dígitos. Na leitura vira o formato brasileiro; e-mail e número fora do
  # padrão nacional aparecem intactos, porque adivinhar aqui seria pior.
  def delivery_recipient_label(recipient)
    value = recipient.to_s.strip
    return value if value.blank? || value.include?("@")

    digits = value.delete("^0-9")
    country = ""
    if digits.length > 11 && digits.start_with?("55")
      country = "+55 "
      digits = digits[2..]
    end
    return value unless [10, 11].include?(digits.length)

    split = digits.length == 11 ? 7 : 6
    "#{country}(#{digits[0, 2]}) #{digits[2...split]}-#{digits[split..]}"
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
