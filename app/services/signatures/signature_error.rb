module Signatures
  # Falha de assinatura. Carrega, quando o provedor informa, o código de negócio
  # e a mensagem original — para log e alerta, nunca para exibir ao usuário: a
  # mensagem de tela é curada por categoria no controller.
  class SignatureError < StandardError
    attr_reader :code, :provider_message

    def initialize(message = nil, code: nil, provider_message: nil)
      super(message)
      @code = code
      @provider_message = provider_message
    end
  end
end
