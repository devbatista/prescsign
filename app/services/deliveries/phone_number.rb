module Deliveries
  # Converte o telefone do paciente para E.164, formato exigido pela API do
  # Twilio. `Patient` guarda apenas dígitos (`normalizes :phone` com `gsub(/\D/)`),
  # sem DDI, então a conversão envolve inferência — e inferir errado significa
  # mandar um documento de saúde para o número de outra pessoa.
  #
  # Por isso só dois formatos são aceitos: número nacional (10 ou 11 dígitos, que
  # recebe o DDI padrão) e número que já traz o DDI. Qualquer outro tamanho é
  # recusado, e o adapter transforma essa recusa em falha explícita da entrega.
  module PhoneNumber
    DEFAULT_COUNTRY_CODE = "55".freeze
    NATIONAL_LENGTHS = [10, 11].freeze
    INTERNATIONAL_LENGTHS = [12, 13].freeze

    module_function

    def to_e164(raw, country_code: DEFAULT_COUNTRY_CODE)
      digits = raw.to_s.gsub(/\D/, "")
      return nil if digits.empty?

      if digits.start_with?(country_code) && INTERNATIONAL_LENGTHS.include?(digits.length)
        return "+#{digits}"
      end

      return "+#{country_code}#{digits}" if NATIONAL_LENGTHS.include?(digits.length)

      nil
    end
  end
end
