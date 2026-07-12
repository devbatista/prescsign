module NavigationHelper
  NavItem = Struct.new(:label, :section, :path, keyword_init: true)

  # Primary nav items filtered by the current persona (mirrors App.vue nav).
  # Fase 4 screens are not built yet, so unbuilt sections point to "#".
  def nav_items
    ctx = access_context

    [
      NavItem.new(label: "Dashboard",       section: :dashboard,            path: app_root_path),
      NavItem.new(label: "Pacientes",       section: :patients,             path: patients_path),
      NavItem.new(label: "Consultas",       section: :consultations,        path: consultations_path),
      NavItem.new(label: "Agenda",          section: :agenda,               path: agenda_path),
      NavItem.new(label: "Emitir Receita",  section: :documents_sign,       path: new_prescription_path),
      NavItem.new(label: "Emitir Atestado", section: :documents_issue,      path: new_medical_certificate_path),
      NavItem.new(label: "Médicos",         section: :responsible_doctors,  path: responsible_doctors_path),
      NavItem.new(label: "Auditoria",       section: :audit_logs,           path: audit_logs_path),
      NavItem.new(label: "Nova Organização", section: :organization_create, path: "#"),
      NavItem.new(label: "Perfil",          section: :profile,              path: "#"),
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
