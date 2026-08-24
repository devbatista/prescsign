module Deliveries
  module Adapters
    # Entrega por WhatsApp via Twilio (Sandbox nos ambientes de teste, número
    # próprio em produção). Sem credencial configurada o canal não fica
    # disponível e uma tentativa falha explicitamente — nunca simula sucesso.
    #
    # Limites do Sandbox que valem para o teste (docs.twilio.com/whatsapp/sandbox):
    # o destinatário precisa ter enviado "join <código>" para o número do
    # sandbox, a adesão expira em três dias e mensagem livre só sai dentro da
    # janela de 24h aberta pela última mensagem do destinatário. Fora dela o
    # Twilio recusa, e a recusa vira falha registrada no DeliveryLog.
    class WhatsappAdapter < BaseAdapter
      PROVIDER_NAME = "twilio".freeze
      CHANNEL_PREFIX = "whatsapp:".freeze

      def self.available?
        config.enabled && config.whatsapp_from.present?
      end

      def self.config
        Rails.application.config.x.twilio
      end

      def call
        unless self.class.available?
          raise Deliveries::PermanentProviderError,
                "Canal WhatsApp indisponível: Twilio não configurado"
        end

        message = client.send_message!(
          from: channel_address(self.class.config.whatsapp_from),
          to: channel_address(recipient_e164),
          body: message_body
        )

        {
          status: "sent",
          provider_name: PROVIDER_NAME,
          provider_message_id: message.sid,
          metadata: {
            channel: "whatsapp",
            provider_status: message.status
          }.merge(metadata)
        }
      end

      private

      def client
        @client ||= Deliveries::TwilioClient.new
      end

      # Número inválido não é falha transitória de provedor: repetir manda o
      # mesmo lixo de novo. Falha permanente, com o valor recusado fora da
      # mensagem para não espalhar contato de paciente em log de erro.
      def recipient_e164
        e164 = Deliveries::PhoneNumber.to_e164(recipient)
        return e164 if e164.present?

        raise Deliveries::PermanentProviderError,
              "Telefone do destinatário não está em formato reconhecido para envio internacional"
      end

      def channel_address(number)
        number.to_s.start_with?(CHANNEL_PREFIX) ? number.to_s : "#{CHANNEL_PREFIX}#{number}"
      end

      # Concordância do texto por tipo de documento: "sua receita ... ela" e
      # "seu atestado médico ... ele". Sem isso a frase sai errada em um dos dois.
      KIND_PHRASES = {
        "prescription" => { possessive: "sua", noun: "receita", pronoun: "ela", signed: "assinada" },
        "medical_certificate" => { possessive: "seu", noun: "atestado médico", pronoun: "ele", signed: "assinado" }
      }.freeze
      DEFAULT_KIND_PHRASE = { possessive: "seu", noun: "documento", pronoun: "ele", signed: "assinado" }.freeze

      # WhatsApp renderiza *negrito* e _itálico_, e linha em branco entre blocos
      # é o que separa a leitura — o token do link de download é longo por
      # natureza (signed_id do Rails) e engole o texto se ficar colado nele.
      def message_body
        [
          greeting,
          "*Baixar o documento*\n#{Documents::PatientLinks.download_url(document)}",
          "*Validar a autenticidade*\n#{Documents::PatientLinks.validation_url(document)}",
          notices
        ].join("\n\n")
      end

      # O paciente reconhece o médico, não a plataforma — mesma razão pela qual
      # o e-mail sai como "Dr. Fulano via PrescSign". Aqui pesa ainda mais: a
      # mensagem chega de um número desconhecido, e o nome do profissional é a
      # única âncora que o paciente tem para não descartar como golpe. Sem
      # perfil de médico ou sem nome do paciente, a frase cai para a impessoal.
      def greeting
        hello = patient_first_name.present? ? "Olá, #{patient_first_name}!" : "Olá!"
        phrase = kind_phrase

        if doctor_reference.blank?
          return "#{hello} #{phrase[:possessive].capitalize} #{phrase[:noun]} " \
                 "já está #{phrase[:signed]} e disponível."
        end

        "#{hello} #{doctor_reference} está lhe enviando #{phrase[:possessive]} " \
          "#{phrase[:noun]} e #{phrase[:pronoun]} já está disponível."
      end

      # `display_name` já traz "Dr."/"Dra."; falta só o artigo concordando.
      def doctor_reference
        profile = document.user&.doctor_profile
        return nil if profile.blank? || profile.display_name.blank?

        "#{profile.female? ? 'A' : 'O'} #{profile.display_name}"
      end

      def notices
        [
          "_Código do documento: #{document.code}_",
          "_O link de download expira em #{Document::PATIENT_DOWNLOAD_TTL.in_days.to_i} dias._"
        ].join("\n")
      end

      def patient_first_name
        document.patient&.full_name.to_s.strip.split.first
      end

      def kind_phrase
        KIND_PHRASES.fetch(document.kind, DEFAULT_KIND_PHRASE)
      end
    end
  end
end
