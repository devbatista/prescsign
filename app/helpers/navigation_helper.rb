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
      NavItem.new(label: "Documentos",      section: :documents,            path: documents_path),
      NavItem.new(label: "Médicos",         section: :doctors,              path: doctors_path),
      NavItem.new(label: "Auditoria",       section: :audit_logs,           path: audit_logs_path),
      NavItem.new(label: "Nova Organização", section: :organization_create, path: new_organization_path),
      NavItem.new(label: "Perfil",          section: :profile,              path: profile_path),
      NavItem.new(label: "Sobre",           section: :about,                path: about_path),
    ].select { |item| ctx.can?(item.section) }
  end

  def active_nav_section?(section)
    active_nav_section == section.to_sym
  end

  def persona_label(persona = current_persona)
    {
      admin: "Administrador",
      organization_responsible: "Responsável da organização",
      doctor: "Médico(a)",
      unknown: "Sem perfil"
    }.fetch(persona, "Sem perfil")
  end

  def persona_label_for_membership(membership)
    {
      "owner" => "Responsável da organização",
      "admin" => "Responsável da organização",
      "doctor" => "Médico(a)",
      "staff" => "Equipe"
    }.fetch(membership.role, "Acesso")
  end

  private

  def active_nav_section
    case controller_path
    when "app/dashboard"
      :dashboard
    when "app/patients"
      :patients
    when "app/consultations"
      :consultations
    when "app/agenda/events"
      :agenda
    when "app/prescriptions"
      :documents
    when "app/medical_certificates"
      :documents
    when "app/documents"
      :documents
    when "app/doctors"
      :doctors
    when "app/audit_logs"
      :audit_logs
    when "app/organizations"
      :organization_create
    when "app/profile"
      :profile
    when "app/pages"
      action_name == "about" ? :about : nil
    end
  end
end
