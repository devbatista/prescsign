class MakeDoctorOptionalOnAuthRefreshTokens < ActiveRecord::Migration[7.1]
  def change
    change_column_null :auth_refresh_tokens, :doctor_id, true
  end
end
