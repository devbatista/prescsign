module NavigationHelper
  NavItem = Struct.new(:label, :section, :path, keyword_init: true)

  # Primary nav items filtered by the current persona (mirrors App.vue nav).
  # Fase 4 screens are not built yet, so unbuilt sections point to "#".
  def nav_items
    ctx = access_context

    [
      NavItem.new(label: "Painel",               section: :dashboard,            path: root_path),
      NavItem.new(label: "Pacientes",            section: :patients,             path: "#"),
      NavItem.new(label: "Consultas",            section: :consultations,        path: "#"),
      NavItem.new(label: "Agenda",               section: :agenda,               path: "#"),
      NavItem.new(label: "Emitir Receita",       section: :documents_sign,       path: "#"),
      NavItem.new(label: "Emitir Atestado",      section: :documents_issue,      path: "#"),
      NavItem.new(label: "Médicos Responsáveis", section: :responsible_doctors,  path: "#"),
      NavItem.new(label: "Auditoria",            section: :audit_logs,           path: "#"),
      NavItem.new(label: "Nova Organização",     section: :organization_create,  path: "#"),
    ].select { |item| ctx.can?(item.section) }
  end

  def persona_label(persona = current_persona)
    {
      admin: "Administrador",
      organization_responsible: "Responsável da organização",
      doctor: "Médico(a)",
      unknown: "Sem perfil"
    }.fetch(persona, "Sem perfil")
  end
end
