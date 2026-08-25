require "base64"
require "json"
require "net/http"
require "uri"

module Signatures
  # Provider de assinatura EVALCryptoCubo.
  #
  # ASSINATURA usa o endpoint APIM v0 (o que foi validado contra a API real):
  #   POST /api/eletronic-signatures/v0/sign/qualified/pdf?profile=&icpbr=
  #   - auth por header Ocp-Apim-Subscription-Key;
  #   - PIN enviado em Base64 (o .env guarda em texto puro; codificamos aqui);
  #   - PDF assinado retorna em documents[].signatures[].value (Base64).
  #
  # VERIFICAÇÃO usa o mesmo endpoint APIM v0 (contrato confirmado contra a API):
  #   POST /api/eletronic-signatures/v0/verify/qualified/pdf?icpbr=
  #   - o PDF assinado vai em documents[].signatures[].value (Base64);
  #   - HTTP 200 -> assinatura válida; documents[].signatures[].signers traz o
  #     titular (subject/CPF), emissor e janela de validade do certificado;
  #   - HTTP 400 code -309 ("Lista de assinaturas vazia") -> PDF sem assinatura;
  #   - HTTP 400 code -725 ("Resumo criptográfico incorreto") -> PDF adulterado.
  #   Os dois últimos são vereditos (valid: false), não erros de sistema.
  class EvalCryptoCuboProvider
    PROVIDER_NAME = "eval_crypto_cubo".freeze
    SIGN_PATH = "/api/eletronic-signatures/v0/sign/qualified/pdf".freeze
    VERIFY_PATH = "/api/eletronic-signatures/v0/verify/qualified/pdf".freeze
    # Códigos de negócio do verify: assinatura ausente / resumo criptográfico
    # incorreto (adulteração). Não são falha de infra — viram valid: false.
    VERIFY_INVALID_CODES = [ -309, -725 ].freeze
    # Certificado travado na certificadora após tentativas de uso incorretas.
    # Retry não resolve: só o desbloqueio no painel da EVAL.
    CERTIFICATE_BLOCKED_CODES = [ -335 ].freeze
    # Erro de configuração nossa. -734: profile inexistente (a política
    # server-side SignPdf{Profile}{Nonicp|Icp} não existe na conta).
    CONFIGURATION_ERROR_CODES = [ -734 ].freeze

    def initialize(
      base_url: Rails.application.config.x.eval_crypto_cubo_provider.base_url,
      api_key: Rails.application.config.x.eval_crypto_cubo_provider.api_key,
      operator_id: Rails.application.config.x.eval_crypto_cubo_provider.operator_id,
      type: Rails.application.config.x.eval_crypto_cubo_provider.type,
      format: Rails.application.config.x.eval_crypto_cubo_provider.format,
      profile: Rails.application.config.x.eval_crypto_cubo_provider.profile,
      icpbr: Rails.application.config.x.eval_crypto_cubo_provider.icpbr,
      alias_name: Rails.application.config.x.eval_crypto_cubo_provider.alias_name,
      use_config_alias: Rails.application.config.x.eval_crypto_cubo_provider.use_config_alias,
      pin: Rails.application.config.x.eval_crypto_cubo_provider.pin,
      timeout_seconds: Rails.application.config.x.eval_crypto_cubo_provider.timeout_seconds
    )
      @base_url = base_url.to_s.chomp("/")
      @api_key = api_key.to_s
      @operator_id = operator_id.to_s
      @type = type.to_s
      @format = format.to_s
      @profile = profile.to_s
      @icpbr = ActiveModel::Type::Boolean.new.cast(icpbr) ? "true" : "false"
      @alias_name = alias_name.to_s
      @use_config_alias = ActiveModel::Type::Boolean.new.cast(use_config_alias)
      @pin = pin.to_s
      @timeout_seconds = timeout_seconds.to_i.positive? ? timeout_seconds.to_i : 30
    end

    def sign_pdf!(document:, pdf_io:, signer:, pin: nil)
      validate_sign_configuration!
      signer_alias = effective_alias(signer)
      signer_pin = pin.presence || @pin
      raise SignatureError, "EVALCryptoCubo signer alias (CPF) is not available" if signer_alias.blank?
      raise SignatureError, "EVALCryptoCubo signing PIN was not provided" if signer_pin.blank?

      response = post_json(
        path: sign_path,
        query: sign_query,
        body: signature_payload(pdf_binary: pdf_io.read, signer_alias: signer_alias, signer_pin: signer_pin)
      )
      build_signature_result(response)
    rescue JSON::ParserError => e
      raise SignatureError, "Invalid EVALCryptoCubo response: #{e.message}"
    rescue Timeout::Error, Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
      raise ProviderUnavailableError, "EVALCryptoCubo provider unavailable: #{e.class}"
    end

    def verify_pdf!(document:, pdf_io:)
      validate_verify_configuration!

      response = execute_post(
        path: VERIFY_PATH,
        query: verify_query,
        body: verification_payload(pdf_binary: pdf_io.read)
      )
      build_verification_result(response)
    rescue JSON::ParserError => e
      raise SignatureError, "Invalid EVALCryptoCubo response: #{e.message}"
    rescue Timeout::Error, Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
      raise ProviderUnavailableError, "EVALCryptoCubo provider unavailable: #{e.class}"
    end

    private

    def validate_sign_configuration!
      raise SignatureError, "EVALCryptoCubo provider base URL is not configured" if @base_url.blank?
      raise SignatureError, "EVALCryptoCubo provider API key is not configured" if @api_key.blank?
      raise SignatureError, "EVALCryptoCubo provider profile is not configured" if @profile.blank?
      raise SignatureError, "EVALCryptoCubo provider format is not configured" if @format.blank?
    end

    # O assinante é o médico: usa o CPF do DoctorProfile. Em development (ou com a
    # flag use_config_alias, p.ex. homologação em modo produção) força o alias do
    # .env — o certificado fixo de teste. Sem perfil/CPF, também cai no de config.
    def effective_alias(signer)
      return @alias_name if use_config_alias? && @alias_name.present?

      signer&.doctor_profile&.cpf.presence || @alias_name
    end

    def use_config_alias?
      Rails.env.development? || @use_config_alias
    end

    def validate_verify_configuration!
      raise SignatureError, "EVALCryptoCubo provider base URL is not configured" if @base_url.blank?
      raise SignatureError, "EVALCryptoCubo provider API key is not configured" if @api_key.blank?
    end

    def sign_path
      SIGN_PATH
    end

    def sign_query
      { profile: @profile, icpbr: @icpbr }
    end

    def verify_query
      { icpbr: @icpbr }
    end

    def signature_payload(pdf_binary:, signer_alias:, signer_pin:)
      {
        format: @format,
        alias: signer_alias,
        # O PIN trafega/entra em texto puro; a API exige Base64.
        pin: Base64.strict_encode64(signer_pin),
        documents: [ { content: Base64.strict_encode64(pdf_binary) } ]
      }
    end

    # O verify v0 lê a assinatura embutida do PDF em documents[].signatures[].value
    # (diferente do sign, que manda o PDF em documents[].content).
    def verification_payload(pdf_binary:)
      { documents: [ { signatures: [ { value: Base64.strict_encode64(pdf_binary) } ] } ] }
    end

    def execute_post(path:, body:, query: nil)
      uri = URI.join("#{@base_url}/", path.delete_prefix("/"))
      uri.query = URI.encode_www_form(query) if query.present?

      request = Net::HTTP::Post.new(uri)
      request["Ocp-Apim-Subscription-Key"] = @api_key if @api_key.present?
      request["Content-Type"] = "application/json"
      request["Cache-Control"] = "no-cache"
      request.body = JSON.generate(body)

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout_seconds
      http.read_timeout = @timeout_seconds

      http.request(request)
    end

    def post_json(path:, body:, query: nil)
      response = execute_post(path: path, body: body, query: query)
      return JSON.parse(response.body) if response.is_a?(Net::HTTPSuccess)

      # Erro do provedor. O corpo pode não ser JSON (ex.: página HTML 504 do
      # Azure Front Door) — daí o rescue no parse.
      parsed_body = JSON.parse(response.body) rescue {}
      raise provider_error_for(response: response, body: parsed_body)
    end

    # Traduz a resposta de erro na exceção que diz o que fazer a respeito:
    # 5xx é indisponibilidade (tente depois); 401/403 e código de política são
    # configuração nossa (o médico não resolve); -335 é certificado bloqueado
    # (retry agrava); PIN recusado é erro do usuário no ato. O que não
    # reconhecemos vira SignatureError genérico — sem culpar o PIN sem certeza.
    def provider_error_for(response:, body:)
      message = provider_error_message(response: response, body: body)
      code = normalized_error_code(body)
      attributes = { code: code, provider_message: body.dig("error", "message").presence }

      return ProviderUnavailableError.new(message, **attributes) if response.is_a?(Net::HTTPServerError)
      return ProviderConfigurationError.new(message, **attributes) if configuration_failure?(response: response, code: code)
      return CertificateBlockedError.new(message, **attributes) if CERTIFICATE_BLOCKED_CODES.include?(code)
      return SignerCredentialError.new(message, **attributes) if signer_credential_failure?(body)

      SignatureError.new(message, **attributes)
    end

    def configuration_failure?(response:, code:)
      CONFIGURATION_ERROR_CODES.include?(code) ||
        response.is_a?(Net::HTTPUnauthorized) ||
        response.is_a?(Net::HTTPForbidden)
    end

    # O código de "PIN incorreto" ainda não foi confirmado contra a API real (o
    # -335 já é o estado seguinte, com o certificado travado). Até ele aparecer,
    # reconhecemos pela mensagem; quando for confirmado, vira constante como os
    # demais e esta heurística sai.
    def signer_credential_failure?(body)
      body.dig("error", "message").to_s.match?(/\b(pin|senha)\b/i)
    end

    def build_signature_result(response)
      signed_document = response.fetch("documents").first
      signature = Array(signed_document["signatures"]).first || {}
      signed_pdf_base64 = signature["value"] || signed_document["content"]
      raise SignatureError, "EVALCryptoCubo response without signed PDF content" if signed_pdf_base64.blank?

      SignatureResult.new(
        # A API devolve o PDF em Base64 MIME (com quebras de linha); decode64 tolera.
        signed_pdf: Base64.decode64(signed_pdf_base64),
        provider: PROVIDER_NAME,
        method: "eval_crypto_cubo_pades",
        signed_at: parse_time(signature["signatureTime"] || signed_document["signatureTime"]) || Time.current,
        timestamped: parse_boolean(response["timestamped"]),
        validation_status: response["validation_status"] || response["validationStatus"] || "not_available",
        raw_metadata: signature_metadata(response: response, signed_document: signed_document)
      )
    rescue KeyError, ArgumentError, NoMethodError => e
      raise SignatureError, "Invalid EVALCryptoCubo response: #{e.message}"
    end

    def build_verification_result(response)
      # 5xx (gateway/manutenção/504 fora do horário) não é veredito de assinatura:
      # sinaliza indisponibilidade para a camada de cima degradar suavemente.
      raise ProviderUnavailableError, verify_error_message(response) if response.is_a?(Net::HTTPServerError)

      parsed = JSON.parse(response.body.presence || "{}")

      if response.is_a?(Net::HTTPSuccess)
        signatures = Array(parsed["documents"]).flat_map { |document| signature_entries(document) }
        return VerificationResult.new(
          provider: PROVIDER_NAME,
          valid: signatures.any?,
          validation_status: signatures.any? ? "valid" : "no_signatures",
          signatures: signatures,
          raw_metadata: verification_metadata(parsed)
        )
      end

      # Não-2xx e não-5xx: vereditos de negócio (assinatura ausente / adulterada)
      # viram valid: false; qualquer outro 4xx (auth/credencial) é erro real.
      if VERIFY_INVALID_CODES.include?(normalized_error_code(parsed))
        return VerificationResult.new(
          provider: PROVIDER_NAME,
          valid: false,
          validation_status: parsed.dig("error", "message").presence || "invalid",
          signatures: [],
          raw_metadata: { "error" => parsed["error"] }.compact
        )
      end

      raise provider_error_for(response: response, body: parsed)
    rescue KeyError, NoMethodError => e
      raise SignatureError, "Invalid EVALCryptoCubo response: #{e.message}"
    end

    # Remove o PDF Base64 (content/signatures[].value) antes de guardar metadados.
    def signature_metadata(response:, signed_document:)
      sanitized_response = response.except("documents")
      sanitized_document = signed_document.except("content")
      if sanitized_document.key?("signatures")
        sanitized_document = sanitized_document.merge(
          "signatures" => Array(signed_document["signatures"]).map { |signature| signature.except("value") }
        )
      end
      sanitized_response.merge("document" => sanitized_document)
    end

    def verification_metadata(response)
      response.merge(
        "documents" => Array(response["documents"]).map { |document| sanitize_verify_document(document) }
      )
    end

    # Tira o PDF Base64 ecoado (content e signatures[].value) dos metadados.
    def sanitize_verify_document(document)
      return document unless document.is_a?(Hash)

      sanitized = document.except("content")
      if sanitized.key?("signatures")
        sanitized = sanitized.merge("signatures" => strip_signature_values(sanitized["signatures"]))
      end
      sanitized
    end

    # Extrai as assinaturas sem o PDF Base64 (signatures[].value): mantém só os
    # dados dos signatários (subject/CPF, emissor, validade, signingTime).
    def signature_entries(document)
      value = document["signatures"] || document["signature"]
      return [] if value.blank?

      strip_signature_values(value)
    end

    def strip_signature_values(signatures)
      list = signatures.is_a?(Array) ? signatures : [ signatures ]
      list.map { |signature| signature.is_a?(Hash) ? signature.except("value") : signature }
    end

    def normalized_error_code(parsed)
      Integer(parsed.dig("error", "code"), exception: false)
    end

    def verify_error_message(response)
      body = JSON.parse(response.body) rescue {}
      provider_error_message(response: response, body: body)
    end

    def parse_boolean(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def parse_time(value)
      return nil if value.blank?

      Time.iso8601(value)
    rescue ArgumentError
      nil
    end

    def provider_error_message(response:, body:)
      code = body.dig("error", "code") || body["error_code"] || body["errorCode"] || response.code
      message = body.dig("error", "message") || body["error_message"] || body["errorMessage"] || response.message
      "EVALCryptoCubo provider returned HTTP #{response.code}: #{code} #{message}".strip
    end
  end
end
