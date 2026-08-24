require "cgi"

module Documents
  # Links que a aplicação manda ao paciente: download do PDF assinado e página
  # pública de validação. Centraliza a montagem da URL base (`config.x.app_*`)
  # para que os canais de entrega não divirjam no endereço que enviam — o
  # e-mail e o WhatsApp precisam apontar para o mesmo lugar.
  class PatientLinks
    class << self
      def download_url(document)
        "#{base_url}/d?token=#{CGI.escape(document.patient_download_token)}"
      end

      def validation_url(document)
        PublicValidationService.new(base_url: base_url).validation_url(document)
      end

      def base_url
        protocol = Rails.application.config.x.app_protocol
        host = Rails.application.config.x.app_host
        port = Rails.application.config.x.app_port.to_i
        standard_port = (protocol == "https" && port == 443) || (protocol == "http" && port == 80)

        return "#{protocol}://#{host}" if standard_port

        "#{protocol}://#{host}:#{port}"
      end
    end
  end
end
