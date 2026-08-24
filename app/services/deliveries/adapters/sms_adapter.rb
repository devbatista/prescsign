module Deliveries
  module Adapters
    # Não existe provedor de SMS integrado. O adapter permanece registrado para
    # que a entrega por este canal falhe alto: antes ele respondia "sent" e o
    # DeliveryLog gravava — junto com a auditoria — uma entrega ao paciente que
    # nunca saiu. Erro permanente porque nenhuma retentativa muda o resultado.
    class SmsAdapter < BaseAdapter
      def call
        raise Deliveries::PermanentProviderError,
              "Canal SMS indisponível: nenhum provedor de envio configurado"
      end
    end
  end
end
