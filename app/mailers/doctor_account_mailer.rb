class DoctorAccountMailer < ApplicationMailer
  # Sent when the organization responsible creates a doctor. Carries a
  # reset-password token so the doctor sets their own password (which also
  # confirms the account on first use — see PasswordsController#update).
  def account_setup
    @user = params.fetch(:user)
    @organization = params.fetch(:organization)
    @token = params.fetch(:token)
    @setup_url = edit_user_password_url(host: login_host, reset_password_token: @token)

    mail(to: @user.email, subject: "Bem-vindo ao PrescSign — defina sua senha")
  end

  private

  # The reset-password screen lives on the login. subdomain. Derive it from the
  # mailer's default host by swapping any leading subdomain for login.
  def login_host
    base = ActionMailer::Base.default_url_options[:host].to_s
    labels = base.split(".")
    base = labels.drop(1).join(".") if labels.length > 2
    "login.#{base}"
  end
end
