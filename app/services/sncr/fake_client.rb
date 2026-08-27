require "base64"
require "json"

module Sncr
  # Cliente simulado da API do SNCR, para exercitar o ciclo completo de numeração
  # (conectar -> solicitar lote -> pool -> consumir na assinatura -> PDF) sem
  # tocar na Anvisa e sem um CPF de prescritor cadastrado no SNCR.
  #
  # Existe porque a numeração real é inacessível em desenvolvimento: a API exige
  # login Gov.br de um CPF com inscrição ativa em CFM/CFMV/CFO (404 "O usuário
  # informado não possui vínculo ativo no conselho") e um `client_url` público
  # `.br` via https (403 "Domínio não autorizado"). Ver seções 4.2.1 e 9 de
  # docs/sncr/SNCR_INTEGRATION.md.
  #
  # Mantém a interface pública de Sncr::Client e as regras de negócio que o
  # manual documenta (lote de até 50 na Notificação, bloco de 1.000 no Controle
  # Especial/Retenção, limite mensal de 3.000 por tipo), para que o código de
  # produção não precise saber que está falando com o simulador.
  #
  # NUNCA roda em produção: Sncr::ClientFactory ignora a flag lá.
  class FakeClient
    NOTIFICACAO_TYPES = %w[NRA NRB NRB2 NRR NRT].freeze
    ESPECIAL_TYPES = %w[RCE RET].freeze
    MAX_NOTIFICACAO_QUANTITY = 50
    ESPECIAL_BLOCK_SIZE = 1_000
    MONTHLY_LIMIT = 3_000
    LOW_BALANCE_THRESHOLD = 50
    TOKEN_TTL = 1.hour

    def initialize(access_token: nil, **)
      @access_token = access_token
    end

    # Emite um JWT sintético (sem assinatura) com o claim `exp`, para o
    # Sncr::TokenStore derivar o TTL como faria com o token real.
    def exchange_token(session_id:)
      raise Sncr::Error, "session_id é obrigatório" if session_id.blank?

      Client::Token.new(access_token: self.class.access_token, token_type: "Bearer")
    end

    def request_notificacao!(receita:, conselho:, uf:, documento:, quantidade:)
      validate_type!(receita, NOTIFICACAO_TYPES)
      validate_presence!(conselho: conselho, uf: uf, documento: documento)
      validate_quantity!(quantidade)

      prefix = prefix_for(documento: documento, sncr_type: receita)
      quantity = quantidade.to_i
      validate_monthly_limit!(prefix, quantity)

      numbers = build_numbers(prefix: prefix, count: quantity)
      balance = MONTHLY_LIMIT - issued_this_month(prefix) - quantity
      Client::Notificacao.new(
        numbers: numbers,
        balance: balance,
        message: balance_message(balance)
      )
    end

    def request_especial_retencao!(conselho:, tipo:, documento:, uf:, cnpj:)
      validate_type!(tipo, ESPECIAL_TYPES)
      validate_presence!(conselho: conselho, uf: uf, documento: documento, cnpj: cnpj)

      prefix = prefix_for(documento: documento, sncr_type: tipo)
      validate_monthly_limit!(prefix, ESPECIAL_BLOCK_SIZE)

      numbers = build_numbers(prefix: prefix, count: ESPECIAL_BLOCK_SIZE)
      Client::EspecialRetencao.new(
        range_start: numbers.first,
        range_end: numbers.last,
        quantity: numbers.size,
        message: "Numeração simulada (SNCR_FAKE). Não tem validade sanitária."
      )
    end

    # JWT sintético compartilhado pelo fluxo de "conexão" simulada ao Gov.br.
    def self.access_token(ttl: TOKEN_TTL)
      header = encode_segment("alg" => "none", "typ" => "JWT")
      payload = encode_segment("sub" => "sncr-fake", "exp" => (Time.current + ttl).to_i)
      "#{header}.#{payload}.sncr-fake"
    end

    def self.encode_segment(hash)
      Base64.urlsafe_encode64(JSON.generate(hash), padding: false)
    end
    private_class_method :encode_segment

    private

    # Prefixo NNNN.N-NN derivado do registro no conselho, para que médicos
    # distintos não colidam na unicidade global de SncrNumbering#number e para
    # que lotes do mesmo médico/tipo sigam a mesma série.
    #
    # Começa com 9: os exemplos oficiais do manual usam AAMM (2411, 2602), então
    # a faixa 9xxx deixa visível no banco e no PDF que o número é de teste. É uma
    # inferência sobre o significado do prefixo — não há regra documentada.
    def prefix_for(documento:, sncr_type:)
      digits = documento.to_s.gsub(/\D/, "").to_i
      serie = Prescription::SNCR_TYPES.index(sncr_type).to_i
      format("9%03d.%d-%02d", digits % 1000, serie, (digits / 1000) % 100)
    end

    # Continua a sequência do que já existe no pool para o prefixo, para que
    # solicitações repetidas não gerem números duplicados (o insert_all! do
    # SncrNumbering estouraria em RecordNotUnique).
    def build_numbers(prefix:, count:)
      first = last_sequence_for(prefix) + 1
      (first...(first + count)).map { |sequence| "#{prefix}.#{sequence.to_s.rjust(7, '0')}" }
    end

    def last_sequence_for(prefix)
      last = SncrNumbering.where("number LIKE ?", "#{prefix}.%").maximum(:number)
      return 0 if last.blank?

      SncrNumbering.split_number(last).last
    end

    def issued_this_month(prefix)
      SncrNumbering.where("number LIKE ?", "#{prefix}.%")
                   .where(obtained_at: Time.current.all_month)
                   .count
    end

    def validate_type!(sncr_type, allowed)
      return if allowed.include?(sncr_type.to_s)

      raise Sncr::Error,
            "SNCR retornou HTTP 400: Tipo da receita inválido. Valores permitidos: [#{allowed.join(', ')}]"
    end

    def validate_presence!(**fields)
      fields.each do |name, value|
        raise Sncr::Error, "SNCR retornou HTTP 400: #{name.to_s.capitalize} não pode ser nulo." if value.blank?
      end
    end

    def validate_quantity!(quantidade)
      quantity = quantidade.to_i
      return if quantity.positive? && quantity <= MAX_NOTIFICACAO_QUANTITY

      raise Sncr::Error,
            "SNCR retornou HTTP 400: Quantidade deve estar entre 1 e #{MAX_NOTIFICACAO_QUANTITY}."
    end

    def validate_monthly_limit!(prefix, quantity)
      return if issued_this_month(prefix) + quantity <= MONTHLY_LIMIT

      raise Sncr::Error,
            "SNCR retornou HTTP 400: Usuário atingiu o limite máximo de receita " \
            "para o tipo de receita no mês atual."
    end

    def balance_message(balance)
      return "Saldo inferior a #{LOW_BALANCE_THRESHOLD} receitas disponíveis." if balance < LOW_BALANCE_THRESHOLD

      "Numeração simulada (SNCR_FAKE). Não tem validade sanitária."
    end
  end
end
