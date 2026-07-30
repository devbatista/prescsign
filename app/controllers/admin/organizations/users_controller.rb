module Admin
  module Organizations
    # Membros de uma organização (aninhado em /organizations/:id/users). Lista os
    # vínculos (OrganizationMembership) daquela org e permite alterar o papel na
    # org, ativar/desativar e remover o vínculo. Escrita restrita a admin.
    #
    # Diferente do módulo de plataforma (Admin::UsersController), aqui o "papel" é
    # o papel NA ORGANIZAÇÃO (owner/admin/doctor/staff), não o papel de plataforma.
    class UsersController < Admin::BaseController
      LAST_OWNER_MSG = "Não é possível remover/desativar/rebaixar o único owner ativo da organização.".freeze

      before_action :set_organization
      before_action :set_membership, only: %i[update_role activate deactivate remove]
      before_action :require_platform_writer!, only: %i[update_role activate deactivate remove]

      def index
        @memberships = @organization.organization_memberships
                                    .joins(:user).includes(:user)
                                    .order(Arel.sql("array_position(ARRAY['owner','admin','doctor','staff'], role), users.email"))
      end

      def update_role
        new_role = params[:role].to_s
        return reject_invalid_role unless OrganizationMembership::ROLES.include?(new_role)
        return redirect_with_last_owner_alert if new_role != "owner" && last_active_owner?(@membership)

        @membership.update!(role: new_role)
        redirect_to admin_organization_users_path(@organization),
          notice: "Papel de #{@membership.user.email} atualizado para #{new_role.humanize}."
      end

      def activate
        @membership.update!(status: "active")
        redirect_to admin_organization_users_path(@organization), notice: "Vínculo ativado."
      end

      def deactivate
        return redirect_with_last_owner_alert if last_active_owner?(@membership)

        @membership.update!(status: "inactive")
        redirect_to admin_organization_users_path(@organization), notice: "Vínculo desativado."
      end

      def remove
        return redirect_with_last_owner_alert if last_active_owner?(@membership)

        member = @membership.user
        ActiveRecord::Base.transaction do
          member.update!(current_organization_id: nil) if member.current_organization_id == @organization.id
          @membership.destroy!
        end
        redirect_to admin_organization_users_path(@organization),
          notice: "#{member.email} removido da organização."
      end

      private

      def set_organization
        @organization = Organization.find(params[:organization_id])
      end

      # A resource aninhada é "users", então :id é o id do usuário; buscamos o
      # vínculo dele nesta organização.
      def set_membership
        @membership = @organization.organization_memberships.find_by!(user_id: params[:id])
      end

      def last_active_owner?(membership)
        membership.role == "owner" && membership.status == "active" &&
          @organization.organization_memberships.active.where(role: "owner").where.not(id: membership.id).none?
      end

      def redirect_with_last_owner_alert
        redirect_to admin_organization_users_path(@organization), alert: LAST_OWNER_MSG
      end

      def reject_invalid_role
        redirect_to admin_organization_users_path(@organization), alert: "Papel de organização inválido."
      end
    end
  end
end
