class DocumentDeliveryMailer < ApplicationMailer
  def notify_document
    @document = params.fetch(:document)
    @validation_url = public_validation_url(@document)
    @download_url = "#{app_base_url}/d?token=#{CGI.escape(@document.patient_download_token)}"
    @download_ttl_days = Document::PATIENT_DOWNLOAD_TTL.in_days.to_i

    mail(
      to: params.fetch(:recipient),
      subject: "Seu documento #{@document.code} está pronto"
    )
  end

  private

  def public_validation_url(document)
    Documents::PublicValidationService.new(base_url: app_base_url).validation_url(document)
  end

  def app_base_url
    protocol = Rails.application.config.x.app_protocol
    host = Rails.application.config.x.app_host
    port = Rails.application.config.x.app_port.to_i
    standard_port = (protocol == "https" && port == 443) || (protocol == "http" && port == 80)

    return "#{protocol}://#{host}" if standard_port

    "#{protocol}://#{host}:#{port}"
  end
end
