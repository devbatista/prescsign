class OrganizationResponsibleMailer < ApplicationMailer
  def signup_invitation
    @organization = params.fetch(:organization)
    @invited_email = params.fetch(:invited_email)
    @invitation_token = params.fetch(:invitation_token)
    @invitation = params.fetch(:invitation)
    @registration_url = new_user_registration_url(
      host: register_host,
      invitation_token: @invitation_token
    )

    mail(to: @invited_email, subject: "Convite de cadastro - responsável da organização")
  end

  private

  # Registration lives on the register. subdomain. Derive it from the mailer's
  # default host by swapping any leading subdomain (login./app.) for register.
  def register_host
    base = ActionMailer::Base.default_url_options[:host].to_s
    labels = base.split(".")
    base = labels.drop(1).join(".") if labels.length > 2
    "register.#{base}"
  end
end
