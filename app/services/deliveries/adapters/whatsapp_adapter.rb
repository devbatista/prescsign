module Deliveries
  module Adapters
    # Mesma situação do SmsAdapter: a Cloud API ainda não está integrada, então
    # a entrega falha em vez de simular sucesso. Ver Deliveries::Adapters::SmsAdapter.
    class WhatsappAdapter < BaseAdapter
      def call
        raise Deliveries::PermanentProviderError,
              "Canal WhatsApp indisponível: nenhum provedor de envio configurado"
      end
    end
  end
end
