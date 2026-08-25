require "rails_helper"
require "securerandom"

RSpec.describe Deliveries::Adapters::WhatsappAdapter do
  let(:doctor) { create_confirmed_doctor }
  let(:patient) { create_patient(doctor:) }
  let(:document) { create_document(doctor:, patient:) }

  describe ".available?" do
    it "exige credencial e remetente do Twilio" do
      configure_twilio(enabled: true, whatsapp_from: "+14155238886")
      expect(described_class).to be_available

      configure_twilio(enabled: true, whatsapp_from: nil)
      expect(described_class).not_to be_available

      configure_twilio(enabled: false, whatsapp_from: "+14155238886")
      expect(described_class).not_to be_available
    end
  end

  describe "#call" do
    before { configure_twilio(enabled: true, whatsapp_from: "+14155238886") }

    it "envia pelo Twilio com prefixo de canal e devolve resposta normalizada" do
      stub_twilio_response(Net::HTTPCreated, "201", { "sid" => "SM123", "status" => "queued" })

      result = described_class.new(document: document, recipient: "(11) 98765-4321").call

      expect(result[:status]).to eq("sent")
      expect(result[:provider_name]).to eq("twilio")
      expect(result[:provider_message_id]).to eq("SM123")
      expect(result[:metadata]).to include(channel: "whatsapp", provider_status: "queued")

      expect(@sent_request.body).to include("From=whatsapp%3A%2B14155238886")
      expect(@sent_request.body).to include("To=whatsapp%3A%2B5511987654321")
      expect(CGI.unescape(@sent_request.body)).to include(document.code)
    end

    it "manda o link de download e o de validação na mensagem" do
      stub_twilio_response(Net::HTTPCreated, "201", { "sid" => "SM124", "status" => "queued" })

      described_class.new(document: document, recipient: patient.phone).call

      body = CGI.unescape(@sent_request.body)
      expect(body).to include("/d?token=")
      expect(body).to include("/validate/#{document.code}")
      expect(body).to include("Código do documento: #{document.code}")
      expect(body).to include("expira em 90 dias")
    end

    # A concordância muda com o tipo do documento: sair "sua receita ... ele"
    # é erro visível para o paciente.
    it "concorda o texto com receita" do
      expect(message_body_for).to include("está lhe enviando sua receita e ela já está disponível")
    end

    it "concorda o texto com atestado" do
      certificate_document = create_certificate_document(doctor:, patient:)
      body = described_class.new(document: certificate_document, recipient: patient.phone).send(:message_body)

      expect(body).to include("está lhe enviando seu atestado médico e ele já está disponível")
    end

    it "credita o profissional com o artigo concordando com o gênero" do
      document.user.doctor_profile.update!(full_name: "Ana Beatriz Costa", gender: "female")
      expect(message_body_for).to include("A Dra. Ana Beatriz Costa está lhe enviando")

      document.user.doctor_profile.update!(full_name: "Carlos Silva", gender: "male")
      expect(message_body_for).to include("O Dr. Carlos Silva está lhe enviando")
    end

    it "saúda pelo primeiro nome do paciente" do
      expect(message_body_for).to start_with("Olá, #{patient.full_name.split.first}!")
    end

    it "cai para a forma impessoal sem perfil de médico" do
      document.user.doctor_profile.destroy!
      document.reload

      expect(message_body_for).to include("Sua receita já está assinada e disponível")
    end

    it "separa os blocos com linha em branco" do
      body = message_body_for
      expect(body).to include("\n\n*Baixar o documento*\n")
      expect(body).to include("\n\n*Validar a autenticidade*\n")
    end

    it "falha de forma permanente quando o Twilio não está configurado" do
      configure_twilio(enabled: false, whatsapp_from: nil)

      expect do
        described_class.new(document: document, recipient: patient.phone).call
      end.to raise_error(Deliveries::PermanentProviderError, /não configurado/)
    end

    # Repetir um envio para número irreconhecível só repete o erro — e, pior,
    # um número mal inferido entregaria documento de saúde a terceiro.
    it "falha de forma permanente quando o telefone não vira E.164" do
      expect do
        described_class.new(document: document, recipient: "12345").call
      end.to raise_error(Deliveries::PermanentProviderError, /formato reconhecido/)
    end

    it "trata mensagem já rejeitada pelo Twilio como falha, mesmo com HTTP 201" do
      stub_twilio_response(
        Net::HTTPCreated, "201",
        { "sid" => "SM125", "status" => "failed", "error_code" => 63_016,
          "error_message" => "Freeform message not allowed outside 24h window" }
      )

      expect do
        described_class.new(document: document, recipient: patient.phone).call
      end.to raise_error(Deliveries::PermanentProviderError, /63016/)
    end

    it "classifica 4xx como falha permanente" do
      stub_twilio_response(Net::HTTPBadRequest, "400", { "code" => 21_211, "message" => "Invalid To" })

      expect do
        described_class.new(document: document, recipient: patient.phone).call
      end.to raise_error(Deliveries::PermanentProviderError, /21211/)
    end

    it "classifica limite de taxa e 5xx como falha transitória" do
      stub_twilio_response(Net::HTTPTooManyRequests, "429", { "message" => "Too Many Requests" })
      expect do
        described_class.new(document: document, recipient: patient.phone).call
      end.to raise_error(Deliveries::TransientProviderError)

      stub_twilio_response(Net::HTTPServiceUnavailable, "503", { "message" => "Service Unavailable" })
      expect do
        described_class.new(document: document, recipient: patient.phone).call
      end.to raise_error(Deliveries::TransientProviderError)
    end
  end

  private

  def message_body_for
    described_class.new(document: document.reload, recipient: patient.phone).send(:message_body)
  end

  def create_certificate_document(doctor:, patient:)
    certificate = MedicalCertificate.create!(
      doctor: doctor,
      patient: patient,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Atestado para repouso",
      issued_on: Date.current,
      rest_start_on: Date.current,
      rest_end_on: Date.current + 2.days,
      status: "draft"
    )

    Document.create!(
      doctor: doctor,
      patient: patient,
      documentable: certificate,
      kind: "medical_certificate",
      code: SecureRandom.alphanumeric(10).upcase,
      status: "issued",
      issued_on: Date.current,
      current_version: 1,
      signed_at: Time.current
    )
  end

  def configure_twilio(enabled:, whatsapp_from:)
    options = ActiveSupport::OrderedOptions.new
    options.enabled = enabled
    options.account_sid = enabled ? "AC123" : nil
    options.auth_token = enabled ? "token" : nil
    options.whatsapp_from = whatsapp_from
    options.base_url = "https://api.twilio.com"
    options.timeout_seconds = 8
    allow(Rails.application.config.x).to receive(:twilio).and_return(options)
  end

  def stub_twilio_response(klass, code, payload)
    response = klass.new("1.1", code, "")
    allow(response).to receive(:body).and_return(JSON.generate(payload))
    allow_any_instance_of(Net::HTTP).to receive(:request) do |_http, request|
      @sent_request = request
      response
    end
  end

  def create_confirmed_doctor
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    doctor = Doctor.create!(
      full_name: "Dra Whats #{suffix}",
      email: "whats.#{suffix}@example.com",
      cpf: "12345#{cpf_suffix}",
      license_number: "CRM#{suffix}",
      license_state: "SP",
      password: "password123",
      password_confirmation: "password123"
    )
    doctor.confirm
    doctor.reload
  end

  def create_patient(doctor:)
    suffix = SecureRandom.hex(4)
    cpf_suffix = suffix.hex.to_s.rjust(6, "0")[0, 6]
    Patient.create!(
      doctor: doctor,
      full_name: "Paciente Whats #{suffix}",
      cpf: "67890#{cpf_suffix}",
      birth_date: Date.new(1990, 1, 1),
      email: "paciente.whats.#{suffix}@example.com",
      phone: "11987654321"
    )
  end

  def create_document(doctor:, patient:)
    prescription = Prescription.create!(
      doctor: doctor,
      patient: patient,
      code: SecureRandom.alphanumeric(10).upcase,
      content: "Conteudo inicial",
      issued_on: Date.current,
      status: "draft"
    )

    Document.create!(
      doctor: doctor,
      patient: patient,
      documentable: prescription,
      kind: "prescription",
      code: SecureRandom.alphanumeric(10).upcase,
      status: "issued",
      issued_on: Date.current,
      current_version: 1,
      signed_at: Time.current
    )
  end
end
