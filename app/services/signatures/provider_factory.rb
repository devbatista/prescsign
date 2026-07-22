module Signatures
  class ProviderFactory
    def self.build
      case Rails.application.config.x.signature_provider.to_s
      when "icp_brasil"
        Signatures::IcpBrasilProvider.new
      when "eval_crypto_cubo"
        Signatures::EvalCryptoCuboProvider.new
      else
        Signatures::InternalProvider.new
      end
    end
  end
end
