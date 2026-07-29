module AdminHelper
  ORGANIZATION_KIND_LABELS = {
    "autonomo" => "Autônomo",
    "clinica" => "Clínica",
    "hospital" => "Hospital"
  }.freeze

  # Inline SVG icons (Lucide-style, 20×20, stroke=currentColor) so nav items and
  # buttons stay self-contained (no icon font / external asset).
  ADMIN_ICON_PATHS = {
    "dashboard" => '<rect x="3" y="3" width="7" height="9" rx="1"/><rect x="14" y="3" width="7" height="5" rx="1"/><rect x="14" y="12" width="7" height="9" rx="1"/><rect x="3" y="16" width="7" height="5" rx="1"/>',
    "building" => '<path d="M3 21h18"/><path d="M5 21V5a2 2 0 0 1 2-2h6a2 2 0 0 1 2 2v16"/><path d="M15 21V9h2a2 2 0 0 1 2 2v10"/><path d="M9 7h2"/><path d="M9 11h2"/><path d="M9 15h2"/>',
    "users" => '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/>',
    "shield" => '<path d="M12 22s8-4 8-10V5l-8-3-8 3v7c0 6 8 10 8 10z"/><path d="m9 12 2 2 4-4"/>',
    "mail" => '<rect x="2" y="4" width="20" height="16" rx="2"/><path d="m22 7-10 6L2 7"/>',
    "bell" => '<path d="M6 8a6 6 0 0 1 12 0c0 7 3 9 3 9H3s3-2 3-9"/><path d="M10.3 21a1.94 1.94 0 0 0 3.4 0"/>',
    "search" => '<circle cx="11" cy="11" r="8"/><path d="m21 21-4.3-4.3"/>',
    "settings" => '<circle cx="12" cy="12" r="3"/><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33 1.65 1.65 0 0 0-1 1.51V21a2 2 0 0 1-4 0v-.09A1.65 1.65 0 0 0 9 19.4a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82 1.65 1.65 0 0 0-1.51-1H3a2 2 0 0 1 0-4h.09A1.65 1.65 0 0 0 4.6 9a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33H9a1.65 1.65 0 0 0 1-1.51V3a2 2 0 0 1 4 0v.09a1.65 1.65 0 0 0 1 1.51 1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82V9a1.65 1.65 0 0 0 1.51 1H21a2 2 0 0 1 0 4h-.09a1.65 1.65 0 0 0-1.51 1z"/>',
    "panel" => '<rect x="3" y="3" width="18" height="18" rx="2"/><path d="M9 3v18"/>',
    "logout" => '<path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4"/><path d="m16 17 5-5-5-5"/><path d="M21 12H9"/>'
  }.freeze

  def admin_icon(name, css: "h-5 w-5")
    paths = ADMIN_ICON_PATHS[name.to_s]
    return "".html_safe if paths.nil?

    content_tag(:svg, paths.html_safe,
      class: css, viewbox: "0 0 24 24", fill: "none", stroke: "currentColor",
      "stroke-width": "1.8", "stroke-linecap": "round", "stroke-linejoin": "round",
      "aria-hidden": "true")
  end

  def admin_nav_link(label, path, icon:, active:)
    link_to(path, class: class_names("admin-nav-link", "is-active" => active)) do
      concat admin_icon(icon)
      concat content_tag(:span, label)
    end
  end

  def admin_nav_soon(label, icon:)
    content_tag(:span, class: "admin-nav-muted") do
      concat admin_icon(icon)
      concat content_tag(:span, label)
      concat content_tag(:span, "em breve", class: "ml-auto rounded-full border border-[var(--admin-border)] px-2 py-0.5 text-[10px] uppercase tracking-wide")
    end
  end

  def admin_organization_kind_label(kind)
    ORGANIZATION_KIND_LABELS.fetch(kind.to_s, kind.to_s.humanize)
  end

  def admin_organization_status_pill(active)
    if active
      content_tag(:span, "Ativa", class: "admin-pill admin-pill-ok")
    else
      content_tag(:span, "Inativa", class: "admin-pill admin-pill-off")
    end
  end

  # :pending | :accepted | :expired — "expirado" cobre o revogado (revoke expira
  # o convite), então não há status próprio de "revogado".
  def admin_invitation_status(invitation)
    return :accepted if invitation.accepted?
    return :expired if invitation.expired?

    :pending
  end

  def admin_invitation_status_pill(invitation)
    case admin_invitation_status(invitation)
    when :accepted
      content_tag(:span, "Aceito", class: "admin-pill admin-pill-ok")
    when :expired
      content_tag(:span, "Expirado", class: "admin-pill admin-pill-off")
    else
      content_tag(:span, "Pendente", class: "admin-pill admin-pill-warn")
    end
  end

  def admin_organization_address(organization)
    line = [
      [organization.street, organization.number].compact_blank.join(", "),
      organization.complement,
      organization.district,
      [organization.city, organization.state].compact_blank.join(" - "),
      organization.zip_code
    ].compact_blank.join(" · ")
    line.presence
  end
end
