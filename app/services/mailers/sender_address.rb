module Mailers
  # Monta o header From: completo ("Nome" <endereco>).
  #
  # O endereço nunca muda: precisa ser o do domínio verificado no SES, porque é
  # ele que carrega a assinatura DKIM e o alinhamento de DMARC. Enviar em nome
  # do domínio do médico faria a mensagem chegar como não-autenticada. O que
  # varia é apenas o nome exibido, e por público:
  #
  #   - e-mails da plataforma (convite, senha, setup de conta) → "PrescSign";
  #   - e-mails ao paciente → "Dr. Fulano via PrescSign", porque o paciente
  #     reconhece o médico, não a plataforma.
  module SenderAddress
    module_function

    # Remetente institucional, usado como default de todos os mailers.
    def default
      build(brand_name)
    end

    # Remetente para mensagens disparadas por um profissional a terceiros. Cai
    # no institucional quando não há nome (documento sem perfil de médico).
    def on_behalf_of(name)
      return default if name.blank?

      build("#{name} via #{brand_name}")
    end

    def build(display_name)
      address = Mail::Address.new(from_email)
      address.display_name = display_name
      address.format
    end

    def brand_name
      Rails.application.config.x.smtp.from_name
    end

    def from_email
      Rails.application.config.x.smtp.from_email
    end
  end
end
