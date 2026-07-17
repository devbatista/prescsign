require "base64"
require "json"
require "net/http"
require "uri"

module Signatures
  class EvalCryptoCuboProvider
    PROVIDER_NAME = "eval_crypto_cubo".freeze

    def initialize(
      base_url: Rails.application.config.x.eval_crypto_cubo_provider.base_url,
      api_key: Rails.application.config.x.eval_crypto_cubo_provider.api_key,
      operator_id: Rails.application.config.x.eval_crypto_cubo_provider.operator_id,
      type: Rails.application.config.x.eval_crypto_cubo_provider.type,
      format: Rails.application.config.x.eval_crypto_cubo_provider.format,
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
      raise SignatureError, "EVALCryptoCubo provider operator ID is not configured" if @operator_id.blank?
      raise SignatureError, "EVALCryptoCubo provider type is not configured" if @type.blank?
      raise SignatureError, "EVALCryptoCubo provider format is not configured" if @format.blank?
    end

    def validate_verify_configuration!
      raise SignatureError, "EVALCryptoCubo provider base URL is not configured" if @base_url.blank?
      raise SignatureError, "EVALCryptoCubo provider verify type is not configured" if @verify_type.blank?
      raise SignatureError, "EVALCryptoCubo provider verify format is not configured" if @verify_format.blank?
    end

    def sign_path
      "/api/v1/electronic-signature-v4/#{escape(@operator_id)}/#{escape(@type)}/#{escape(@format)}/sign"
    end

    def verify_path
      segments = [ "api", "v1", "electronic-signature-v4", "verify", @verify_type, @verify_format ]
      segments << @verify_signer if @verify_signer.present?
      segments << @verify_package if @verify_package.present?
      "/#{segments.map { |segment| escape(segment) }.join("/")}"
    end

    def signature_payload(document:, pdf_binary:, signer:)
      payload = base_payload(pdf_binary)
      payload[:alias] = @alias_name if @alias_name.present?
      payload[:pin] = @pin if @pin.present?
      payload
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

    def post_json(path:, body:)
      uri = URI.join("#{@base_url}/", path.delete_prefix("/"))
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}" if @api_key.present?
      request["Content-Type"] = "application/json"
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
      signed_pdf_base64 = signed_document.fetch("content")

      SignatureResult.new(
        signed_pdf: Base64.strict_decode64(signed_pdf_base64),
        provider: PROVIDER_NAME,
        method: "eval_crypto_cubo_pades",
        signed_at: parse_time(signed_document["signatureTime"]) || Time.current,
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

    def signature_metadata(response:, signed_document:)
      sanitized_response = response.except("documents")
      sanitized_document = signed_document.except("content")
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
      code = body["error_code"] || body["errorCode"] || response.code
      message = body["error_message"] || body["errorMessage"] || response.message
      "EVALCryptoCubo provider returned HTTP #{response.code}: #{code} #{message}".strip
    end

    def escape(value)
      URI.encode_www_form_component(value.to_s)
    end
  end
end
