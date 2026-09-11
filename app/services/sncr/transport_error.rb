module Sncr
  # A Anvisa não respondeu (timeout, DNS, conexão recusada). O desfecho da
  # requisição é **desconhecido**, não negativo: ela pode ter sido processada do
  # outro lado.
  #
  # Para RCE/RET isso significa cota possivelmente gasta — e é por isso que este
  # caso é separado do erro comum. Quem conta cota trata `unknown`, que bloqueia,
  # e não `failed`, que libera.
  class TransportError < Error; end
end
