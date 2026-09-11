module Sncr
  # Barrado por nós, antes de tocar a Anvisa, por limite conhecido dela.
  #
  # A mensagem é escrita para o médico ler na tela — não é diagnóstico de time,
  # não é incidente, e não deve ir para o Sentry. Quem trata precisa capturá-la
  # **antes** de Sncr::Error, de quem ela herda.
  class QuotaExceeded < Error; end
end
