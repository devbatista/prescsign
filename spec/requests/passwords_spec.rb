require "rails_helper"

RSpec.describe "Passwords (login. subdomain)", type: :request do
  let(:organization) { create_organization }

  before { use_login_host! }

  it "sets a password and confirms an account created unconfirmed" do
    # Simulates a doctor created by the responsible: unconfirmed, with a random
    # password, receiving a reset-password token to define their own password.
    user = create_user(organization: organization)
    user.update_columns(confirmed_at: nil)
    raw_token = user.send(:set_reset_password_token)

    put "/reset-password", params: {
      user: { reset_password_token: raw_token, password: "novaSenha123", password_confirmation: "novaSenha123" }
    }

    expect(response).to have_http_status(:found)
    user.reload
    expect(user.confirmed_at).to be_present
    expect(user.valid_password?("novaSenha123")).to be(true)
  end
end
