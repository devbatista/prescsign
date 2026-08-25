module Signatures
  # A configuração da integração está errada do nosso lado: profile inexistente,
  # subscription key inválida/expirada, alias sem registro na conta. O médico não
  # tem como resolver e nenhuma assinatura passa até alguém corrigir — por isso
  # alerta o time em vez de pedir que ele tente de novo.
  class ProviderConfigurationError < SignatureError; end
end
