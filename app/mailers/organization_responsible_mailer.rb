require "cgi"

class OrganizationResponsibleMailer < ApplicationMailer
  def signup_invitation
    @organization = params.fetch(:organization)
    @invited_email = params.fetch(:invited_email)
    @invitation_token = params.fetch(:invitation_token)
    @invitation = params.fetch(:invitation)
    @registration_url = "#{app_base_url}/auth/register?invitation_token=#{CGI.escape(@invitation_token)}"

    mail(to: @invited_email, subject: "Convite de cadastro - responsável da organização")
  end

  private

  def app_base_url
    protocol = Rails.application.config.x.app_protocol
    host = Rails.application.config.x.app_host
    port = Rails.application.config.x.app_port.to_i
    standard_port = (protocol == "https" && port == 443) || (protocol == "http" && port == 80)

    return "#{protocol}://#{host}" if standard_port

    "#{protocol}://#{host}:#{port}"
  end
end
