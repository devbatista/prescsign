class ConsultationPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    (same_organization_record? && (organization_member? || support?)) || admin?
  end

  def create?
    return false unless user.present?
    return false if support?
    return true if admin?

    organization_member?
  end

  def update?
    return false unless user.present?
    return false if support?

    (same_organization_record? && organization_member?) || admin?
  end

  # A consulta mistura agenda (paciente, horário, médico, status) com conteúdo
  # clínico, e quem vê a agenda não vê, por isso, o conteúdo. Decisão de
  # 16/10/2026 (sigilo médico; LGPD, art. 11):
  #
  # Queixa principal — o motivo informado no agendamento. É da agenda da
  # organização: recepção e médicos dela veem e registram. Admin e suporte da
  # plataforma não, mesmo com vínculo na organização (é o vínculo que dá acesso
  # ao painel) — a menos que sejam o próprio médico da consulta.
  def chief_complaint?
    return true if clinical_notes?
    return false if admin? || support?

    same_organization_record? && organization_member?
  end

  # Diagnóstico e notas — só o médico da consulta. Nem a recepção, nem outro
  # médico da organização, nem a equipe da plataforma.
  def clinical_notes?
    user.present? && record.user_id.present? && record.user_id == user.id
  end

  def destroy?
    return false unless user.present?
    return false if support?

    (same_organization_record? && organization_member?) || admin?
  end

  class Scope < Scope
    def resolve
      return scope.none unless user.present?
      return scope.all if user.respond_to?(:admin?) && user.admin?
      return scope.none if current_organization_id.blank?

      tenant_scope = scope.where(organization_id: current_organization_id)
      return tenant_scope if user.membership_for(current_organization_id).present? || support?

      scope.none
    end

    private

    def current_organization_id
      Current.organization&.id || user.current_organization_id
    end
  end
end
