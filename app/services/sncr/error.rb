module Sncr
  # Erro de integração com a API do SNCR (Anvisa): falha de configuração,
  # autenticação, requisição de numeração, resposta inválida ou indisponibilidade.
  class Error < StandardError; end
end
