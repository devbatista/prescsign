module Signatures
  # Certificado do assinante bloqueado na certificadora (EVAL código -335, após
  # tentativas de uso com PIN incorreto). Repetir a assinatura NÃO resolve e
  # tende a agravar o bloqueio — o destravamento é feito no painel da EVAL.
  # Por isso a mensagem ao usuário desencoraja o retry, ao contrário das demais.
  class CertificateBlockedError < SignatureError; end
end
