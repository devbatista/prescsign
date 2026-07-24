module App
  module Sncr
    # Área do painel (app.) do pool de numerações SNCR do médico (Opção B):
    # exibe o saldo por tipo, permite conectar ao Gov.br e solicitar lotes de
    # numeração, que são importados para o pool (SncrNumbering). Visível apenas
    # para a persona médico.
    #
    # Usa `::Sncr::` / `::SncrNumbering` (top-level) para não colidir com App::Sncr.
    class NumberingsController < ApplicationController
      NOTIFICACAO_TYPES = %w[NRA NRB NRB2 NRR NRT].freeze
      ESPECIAL_TYPES = %w[RCE RET].freeze

      TYPE_LABELS = {
        "NRA" => "Notificação de Receita A (entorpecentes)",
        "NRB" => "Notificação de Receita B (psicotrópicos)",
        "NRB2" => "Notificação de Receita B2 (retinoides sistêmicos)",
        "NRR" => "Notificação Especial (retinoides)",
        "NRT" => "Notificação de Talidomida",
        "RCE" => "Receita de Controle Especial (C1/C5)",
        "RET" => "Receita Sujeita a Retenção (antimicrobianos, GLP-1)"
      }.freeze

      before_action :require_doctor!

      def index
        @types = ::Prescription::SNCR_TYPES
        @type_labels = TYPE_LABELS
        @balance = ::SncrNumbering.balance_for(doctor_profile)
        @connected = sncr_authenticated?
      end

      def create
        sncr_type = params[:sncr_type].to_s
        return redirect_to(sncr_numberings_path, alert: "Tipo de receita inválido.") unless valid_type?(sncr_type)
        return redirect_to(sncr_auth_start_path(state: sncr_numberings_path)) unless sncr_authenticated?

        count = request_batch!(sncr_type)
        redirect_to sncr_numberings_path,
                    notice: "#{count} numeração(ões) de #{sncr_type} obtidas do SNCR."
      rescue ::Sncr::Error => e
        redirect_to sncr_numberings_path, alert: "Falha ao obter numeração: #{e.message}"
      rescue ActiveRecord::RecordNotUnique
        redirect_to sncr_numberings_path, alert: "Essas numerações já haviam sido importadas."
      end

      private

      def valid_type?(sncr_type)
        ::Prescription::SNCR_TYPES.include?(sncr_type)
      end

      def request_batch!(sncr_type)
        client = ::Sncr::Client.new(access_token: access_token)

        if NOTIFICACAO_TYPES.include?(sncr_type)
          result = client.request_notificacao!(
            receita: sncr_type,
            conselho: conselho,
            uf: doctor_profile.license_state,
            documento: documento,
            quantidade: 50
          )
          ::SncrNumbering.import_numbers!(doctor_profile: doctor_profile, sncr_type: sncr_type, numbers: result.numbers)
        else
          result = client.request_especial_retencao!(
            conselho: conselho,
            tipo: sncr_type,
            documento: documento,
            uf: doctor_profile.license_state,
            cnpj: platform_cnpj
          )
          ::SncrNumbering.import_range!(
            doctor_profile: doctor_profile,
            sncr_type: sncr_type,
            first: result.range_start,
            last: result.range_end
          )
        end
      end

      def require_doctor!
        return if current_persona == :doctor && doctor_profile

        redirect_to app_root_path, alert: "Área disponível apenas para médicos."
      end

      def doctor_profile
        @doctor_profile ||= current_user.doctor_profile
      end

      def sncr_authenticated?
        access_token.present?
      end

      def access_token
        session[:sncr]&.dig("access_token")
      end

      # Conselho/documento a partir do perfil. Simplificação: assume CRM, pois o
      # DoctorProfile ainda não separa conselho do número (license_number). A
      # refinar com um campo próprio de conselho (CRM/CRMV/CRO).
      def conselho
        "CRM"
      end

      def documento
        doctor_profile.license_number
      end

      def platform_cnpj
        Rails.application.config.x.sncr.platform_cnpj
      end
    end
  end
end
