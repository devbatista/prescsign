module Sncr
  # Erro de integração com a API do SNCR (Anvisa): falha de configuração,
  # autenticação, requisição de numeração, resposta inválida ou indisponibilidade.
  #
  # Subclasses em arquivos próprios (convenção do Zeitwerk): TransportError e
  # QuotaExceeded.
  class Error < StandardError
    attr_reader :http_status

    def initialize(message = nil, http_status: nil)
      super(message)
      @http_status = http_status
    end
  end
end
