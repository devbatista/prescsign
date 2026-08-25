module Signatures
  # Credencial do assinante recusada (PIN incorreto). É erro do usuário no ato
  # da assinatura: tentar de novo com o PIN certo resolve — mas insistir errado
  # leva ao CertificateBlockedError, então a mensagem avisa disso.
  class SignerCredentialError < SignatureError; end
end
