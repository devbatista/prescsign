module Signatures
  class ProviderFactory
    # Sem fallback: um valor desconhecido cairia no InternalProvider, que não
    # assina o PDF. O boot já barra isso (Prescsign::AppConfig), mas a factory
    # não deve ser o lugar onde um erro de configuração vira documento sem
    # assinatura.
    def self.build
      case Rails.application.config.x.signature_provider.to_s
      when "internal"
        Signatures::InternalProvider.new
      when "icp_brasil"
        Signatures::IcpBrasilProvider.new
      when "eval_crypto_cubo"
        Signatures::EvalCryptoCuboProvider.new
      else
        raise Signatures::ProviderConfigurationError,
              "Unknown signature provider: #{Rails.application.config.x.signature_provider.inspect}"
      end
    end
  end
end
