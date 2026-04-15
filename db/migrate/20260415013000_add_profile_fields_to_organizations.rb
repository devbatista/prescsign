class AddProfileFieldsToOrganizations < ActiveRecord::Migration[7.1]
  def change
    add_column :organizations, :legal_name, :string
    add_column :organizations, :trade_name, :string
    add_column :organizations, :cnpj, :string
    add_column :organizations, :email, :string
    add_column :organizations, :phone, :string
    add_column :organizations, :zip_code, :string
    add_column :organizations, :street, :string
    add_column :organizations, :number, :string
    add_column :organizations, :complement, :string
    add_column :organizations, :district, :string
    add_column :organizations, :city, :string
    add_column :organizations, :state, :string, limit: 2
    add_column :organizations, :country, :string, limit: 2
    add_column :organizations, :metadata, :jsonb, null: false, default: {}

    add_index :organizations, :cnpj, unique: true, where: "cnpj IS NOT NULL"

    add_check_constraint :organizations,
                         "cnpj IS NULL OR (trim(cnpj) <> '' AND char_length(cnpj) = 14)",
                         name: "chk_organizations_cnpj_length"
    add_check_constraint :organizations,
                         "kind = 'autonomo' OR cnpj IS NOT NULL",
                         name: "chk_organizations_cnpj_required_for_legal_entity"
    add_check_constraint :organizations,
                         "kind = 'autonomo' OR legal_name IS NOT NULL",
                         name: "chk_organizations_legal_name_required_for_legal_entity"
  end
end
