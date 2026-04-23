class OrganizationResponsibleMailer < ApplicationMailer
  def signup_invitation
    @organization = params.fetch(:organization)
    @user = params.fetch(:user)
    @confirmation_token = params.fetch(:confirmation_token)
    @confirmation_url = user_confirmation_url(confirmation_token: @confirmation_token)

    mail(to: @user.email, subject: "Convite de cadastro - responsável da organização")
  end

  def existing_account_invitation
    @organization = params.fetch(:organization)
    @user = params.fetch(:user)

    mail(to: @user.email, subject: "Você foi adicionado como responsável da organização")
  end
end
