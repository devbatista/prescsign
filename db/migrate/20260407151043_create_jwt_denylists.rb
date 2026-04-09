class CreateJwtDenylists < ActiveRecord::Migration[7.1]
  def change
    create_table :jwt_denylists, id: :uuid, if_not_exists: true do |t|
      t.string :jti, null: false
      t.datetime :exp, null: false
    end

    add_index :jwt_denylists, :jti, unique: true unless index_exists?(:jwt_denylists, :jti)
    add_index :jwt_denylists, :exp unless index_exists?(:jwt_denylists, :exp)
  end
end
