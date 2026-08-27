module Sncr
  # Decide entre o cliente real do SNCR e o simulado (Sncr::FakeClient), no mesmo
  # espírito de Signatures::ProviderFactory. Todo call site deve construir o
  # cliente por aqui, nunca instanciando Sncr::Client direto.
  #
  # O modo simulado só vale em development (ver Prescsign::AppConfig#sncr_options):
  # em produção seria falsificação de documento sanitário — número inventado num
  # PDF assinado de verdade — e em test tornaria a suíte dependente do .env da
  # máquina. Nos specs, ligue com `with_sncr_fake`.
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
