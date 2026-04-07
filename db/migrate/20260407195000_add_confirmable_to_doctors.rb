class AddConfirmableToDoctors < ActiveRecord::Migration[7.1]
  def change
    add_column :doctors, :confirmation_token, :string
    add_column :doctors, :confirmed_at, :datetime
    add_column :doctors, :confirmation_sent_at, :datetime
    add_column :doctors, :unconfirmed_email, :string

    add_index :doctors, :confirmation_token, unique: true
  end
end
