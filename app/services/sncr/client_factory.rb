module Sncr
  # Decide entre o cliente real do SNCR e o simulado (Sncr::FakeClient), no mesmo
  # espírito de Signatures::ProviderFactory. Todo call site deve construir o
  # cliente por aqui, nunca instanciando Sncr::Client direto.
  #
  # O modo simulado é ignorado em produção — numeração de controlado é documento
  # sanitário, e um número inventado num PDF assinado de verdade é falsificação.
  # A flag só vale fora de produção, mesmo que SNCR_FAKE=true vaze para o
  # ambiente (ver Prescsign::AppConfig#sncr_options).
  class ClientFactory
    def self.build(access_token: nil, **options)
      return FakeClient.new(access_token: access_token) if fake?

      Client.new(access_token: access_token, **options)
    end

    def self.fake?
      Rails.application.config.x.sncr.fake == true
    end
  end
end
