module Signatures
  # Falha temporária do provedor (indisponibilidade/timeout/erro de gateway 5xx):
  # não é culpa das credenciais do médico; sugere "tente novamente".
  class ProviderUnavailableError < SignatureError; end
end
