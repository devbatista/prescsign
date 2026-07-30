class UnifyOrganizationAdminIntoOwner < ActiveRecord::Migration[7.1]
  # "admin" deixa de ser papel de organização: o responsável/administrador de uma
  # org passa a ser "owner". `admin` fica exclusivo do back-office (user_roles).
  # Converte os vínculos existentes e restringe o check constraint de papel.
  def up
    execute <<~SQL.squish
      UPDATE organization_memberships SET role = 'owner' WHERE role = 'admin'
    SQL

    remove_check_constraint :organization_memberships,
      name: "chk_organization_memberships_role_values"
    add_check_constraint :organization_memberships,
      "role::text = ANY (ARRAY['owner'::varchar, 'doctor'::varchar, 'staff'::varchar]::text[])",
      name: "chk_organization_memberships_role_values"
  end

  def down
    remove_check_constraint :organization_memberships,
      name: "chk_organization_memberships_role_values"
    add_check_constraint :organization_memberships,
      "role::text = ANY (ARRAY['owner'::varchar, 'admin'::varchar, 'doctor'::varchar, 'staff'::varchar]::text[])",
      name: "chk_organization_memberships_role_values"
    # Não revertemos os dados (admin→owner) por não ser possível distinguir os
    # que já eram owner; a distinção admin/owner foi intencionalmente removida.
  end
end
