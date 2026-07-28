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
  # VERIFICAÇÃO ainda mira o contrato electronic-signature-v4 e será migrada para
  # o v0 num passo separado (contrato de verify do v0 ainda não confirmado).
  class EvalCryptoCuboProvider
    PROVIDER_NAME = "eval_crypto_cubo".freeze
    SIGN_PATH = "/api/eletronic-signatures/v0/sign/qualified/pdf".freeze

    def initialize(
      base_url: Rails.application.config.x.eval_crypto_cubo_provider.base_url,
      api_key: Rails.application.config.x.eval_crypto_cubo_provider.api_key,
      operator_id: Rails.application.config.x.eval_crypto_cubo_provider.operator_id,
      type: Rails.application.config.x.eval_crypto_cubo_provider.type,
      format: Rails.application.config.x.eval_crypto_cubo_provider.format,
      profile: Rails.application.config.x.eval_crypto_cubo_provider.profile,
      icpbr: Rails.application.config.x.eval_crypto_cubo_provider.icpbr,
      alias_name: Rails.application.config.x.eval_crypto_cubo_provider.alias_name,
      pin: Rails.application.config.x.eval_crypto_cubo_provider.pin,
      verify_type: Rails.application.config.x.eval_crypto_cubo_provider.verify_type,
      verify_format: Rails.application.config.x.eval_crypto_cubo_provider.verify_format,
      verify_signer: Rails.application.config.x.eval_crypto_cubo_provider.verify_signer,
      verify_package: Rails.application.config.x.eval_crypto_cubo_provider.verify_package,
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
      @pin = pin.to_s
      @verify_type = verify_type.presence || @type
      @verify_format = verify_format.presence || @format
      @verify_signer = verify_signer.to_s
      @verify_package = verify_package.to_s
      @timeout_seconds = timeout_seconds.to_i.positive? ? timeout_seconds.to_i : 30
    end

    def sign_pdf!(document:, pdf_io:, signer:)
      validate_sign_configuration!

      response = post_json(
        path: sign_path,
        query: sign_query,
        body: signature_payload(document: document, pdf_binary: pdf_io.read, signer: signer)
      )
      build_signature_result(response)
    rescue JSON::ParserError => e
      raise SignatureError, "Invalid EVALCryptoCubo response: #{e.message}"
    rescue Timeout::Error, Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
      raise SignatureError, "EVALCryptoCubo provider unavailable: #{e.class}"
    end

    def verify_pdf!(document:, pdf_io:)
      validate_verify_configuration!

      response = post_json(
        path: verify_path,
        body: verification_payload(document: document, pdf_binary: pdf_io.read)
      )
      build_verification_result(response)
    rescue JSON::ParserError => e
      raise SignatureError, "Invalid EVALCryptoCubo response: #{e.message}"
    rescue Timeout::Error, Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
      raise SignatureError, "EVALCryptoCubo provider unavailable: #{e.class}"
    end

    private

    def validate_sign_configuration!
      raise SignatureError, "EVALCryptoCubo provider base URL is not configured" if @base_url.blank?
      raise SignatureError, "EVALCryptoCubo provider API key is not configured" if @api_key.blank?
      raise SignatureError, "EVALCryptoCubo provider profile is not configured" if @profile.blank?
      raise SignatureError, "EVALCryptoCubo provider alias is not configured" if @alias_name.blank?
      raise SignatureError, "EVALCryptoCubo provider PIN is not configured" if @pin.blank?
      raise SignatureError, "EVALCryptoCubo provider format is not configured" if @format.blank?
    end

    def validate_verify_configuration!
      raise SignatureError, "EVALCryptoCubo provider base URL is not configured" if @base_url.blank?
      raise SignatureError, "EVALCryptoCubo provider verify type is not configured" if @verify_type.blank?
      raise SignatureError, "EVALCryptoCubo provider verify format is not configured" if @verify_format.blank?
    end

    def sign_path
      SIGN_PATH
    end

    def sign_query
      { profile: @profile, icpbr: @icpbr }
    end

    def verify_path
      segments = [ "api", "v1", "electronic-signature-v4", "verify", @verify_type, @verify_format ]
      segments << @verify_signer if @verify_signer.present?
      segments << @verify_package if @verify_package.present?
      "/#{segments.map { |segment| escape(segment) }.join("/")}"
    end

    def signature_payload(document:, pdf_binary:, signer:)
      {
        format: @format,
        alias: @alias_name,
        pin: encoded_pin,
        documents: [ { content: Base64.strict_encode64(pdf_binary) } ]
      }
    end

    # O .env guarda o PIN em texto puro; a API exige Base64.
    def encoded_pin
      Base64.strict_encode64(@pin)
    end

    def verification_payload(document:, pdf_binary:)
      base_payload(pdf_binary, type: @verify_type, format: @verify_format)
    end

    def base_payload(pdf_binary, type: @type, format: @format)
      {
        format: format,
        type: type,
        documents: [
          {
            content: Base64.strict_encode64(pdf_binary)
          }
        ]
      }
    end

    def post_json(path:, body:, query: nil)
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

      response = http.request(request)
      parsed_body = JSON.parse(response.body)
      return parsed_body if response.is_a?(Net::HTTPSuccess)

      raise SignatureError, provider_error_message(response: response, body: parsed_body)
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
      documents = response.fetch("documents")
      signatures = documents.flat_map { |document| signature_entries(document) }
      validation_status = response["validation_status"] || response["validationStatus"] || documents.first&.dig("validationStatus")

      VerificationResult.new(
        provider: PROVIDER_NAME,
        valid: parse_valid(response, documents),
        validation_status: validation_status,
        signatures: signatures,
        raw_metadata: verification_metadata(response)
      )
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
        "documents" => Array(response["documents"]).map { |document| document.except("content") }
      )
    end

    def signature_entries(document)
      value = document["signatures"] || document["signature"]
      return [] if value.blank?
      return value if value.is_a?(Array)

      [value]
    end

    def parse_valid(response, documents)
      value = response["valid"] || response["isValid"] || documents.first&.dig("valid") || documents.first&.dig("isValid")
      return nil if value.nil?

      parse_boolean(value)
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

    def escape(value)
      URI.encode_www_form_component(value.to_s)
    end
  end
end
