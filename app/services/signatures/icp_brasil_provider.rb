require "base64"
require "json"
require "net/http"
require "uri"

module Signatures
  class IcpBrasilProvider
    DEFAULT_PATH = "/signatures/pdf".freeze

    def initialize(
      base_url: Rails.application.config.x.icp_brasil_provider.base_url,
      api_key: Rails.application.config.x.icp_brasil_provider.api_key,
      timeout_seconds: Rails.application.config.x.icp_brasil_provider.timeout_seconds
    )
      @base_url = base_url.to_s.chomp("/")
      @api_key = api_key.to_s
      @timeout_seconds = timeout_seconds.to_i.positive? ? timeout_seconds.to_i : 30
    end

    def sign_pdf!(document:, pdf_io:, signer:)
      raise SignatureError, "ICP-Brasil provider base URL is not configured" if @base_url.blank?
      raise SignatureError, "ICP-Brasil provider API key is not configured" if @api_key.blank?

      response = post_signature_request(document: document, pdf_binary: pdf_io.read, signer: signer)
      build_result(response)
    rescue JSON::ParserError => e
      raise SignatureError, "Invalid ICP-Brasil provider response: #{e.message}"
    rescue Timeout::Error, Errno::ECONNREFUSED, SocketError, Net::OpenTimeout, Net::ReadTimeout => e
      raise SignatureError, "ICP-Brasil provider unavailable: #{e.class}"
    end

    private

    def post_signature_request(document:, pdf_binary:, signer:)
      uri = URI.join("#{@base_url}/", DEFAULT_PATH.delete_prefix("/"))
      request = Net::HTTP::Post.new(uri)
      request["Authorization"] = "Bearer #{@api_key}"
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(
        document_id: document.id,
        document_code: document.code,
        signer_id: signer.id,
        pdf_base64: Base64.strict_encode64(pdf_binary)
      )

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = uri.scheme == "https"
      http.open_timeout = @timeout_seconds
      http.read_timeout = @timeout_seconds

      response = http.request(request)
      raise SignatureError, "ICP-Brasil provider returned HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

      JSON.parse(response.body)
    end

    def build_result(response)
      signed_pdf_base64 = response.fetch("signed_pdf_base64")

      SignatureResult.new(
        signed_pdf: Base64.strict_decode64(signed_pdf_base64),
        provider: response.fetch("provider", "icp_brasil"),
        method: response.fetch("method", "icp_brasil_pades"),
        policy: response["policy"],
        certificate_subject: response["certificate_subject"],
        certificate_issuer: response["certificate_issuer"],
        certificate_serial: response["certificate_serial"],
        certificate_cpf: response["certificate_cpf"],
        signed_at: parse_time(response["signed_at"]) || Time.current,
        timestamped: ActiveModel::Type::Boolean.new.cast(response["timestamped"]),
        validation_status: response["validation_status"],
        raw_metadata: response.fetch("metadata", {})
      )
    rescue KeyError, ArgumentError => e
      raise SignatureError, "Invalid ICP-Brasil provider response: #{e.message}"
    end

    def parse_time(value)
      return nil if value.blank?

      Time.iso8601(value)
    rescue ArgumentError
      nil
    end
  end
end
