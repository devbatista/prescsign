module App
  module Sncr
    # Área do painel (app.) do pool de numerações SNCR do médico (Opção B):
    # exibe o saldo por tipo, permite conectar ao Gov.br e solicitar lotes de
    # numeração, que são importados para o pool (SncrNumbering). Visível apenas
    # para a persona médico.
    #
    # Usa `::Sncr::` / `::SncrNumbering` (top-level) para não colidir com App::Sncr.
    class NumberingsController < ApplicationController
      include SncrErrorReporting
      include SafeInternalRedirects

      before_action :require_doctor!

      def index
        @types = ::Prescription::SNCR_TYPES
        @type_labels = ::Prescription::SNCR_TYPE_LABELS
        @balance = ::SncrNumbering.balance_for(doctor_profile)
        @connected = sncr_authenticated?
        @fake = ::Sncr::ClientFactory.fake?
        @quota = ::Sncr::NumberingQuota.for(doctor_profile)
        # Tipo que faltou na assinatura, para destacar a linha certa em vez de
        # deixar o médico adivinhar entre sete.
        @requested_type = params[:sncr_type].to_s.presence_in(::Prescription::SNCR_TYPES)
        @return_to = safe_internal_path(params[:return_to])
        @recent_requests = ::SncrNumberingRequest.for_doctor(doctor_profile)
                                                 .order(requested_at: :desc)
                                                 .limit(10)
      end

      def create
        sncr_type = params[:sncr_type].to_s
        return_to = safe_internal_path(params[:return_to])
        return redirect_to(sncr_numberings_path, alert: "Tipo de receita inválido.") unless valid_type?(sncr_type)

        unless sncr_authenticated?
          # Preserva a cadeia inteira: depois do Gov.br o médico volta ao painel
          # já com o tipo destacado e o caminho de volta ao documento.
          return redirect_to sncr_auth_start_path(
            state: sncr_numberings_path(sncr_type: sncr_type, return_to: return_to)
          )
        end

        request = request_batch!(sncr_type)
        redirect_to return_to || sncr_numberings_path, notice: success_notice(request, return_to)
      rescue ::Sncr::QuotaExceeded => e
        # Limite conhecido da Anvisa, não incidente: a mensagem já é para o
        # médico e não vai para o Sentry. Precisa vir antes do rescue genérico,
        # porque QuotaExceeded herda de Sncr::Error.
        redirect_to sncr_numberings_path(sncr_type: sncr_type, return_to: return_to), alert: e.message
      rescue ::Sncr::Error => e
        # Config nossa ou regra de negócio da Anvisa (sem vínculo no conselho,
        # limite mensal): em qualquer caso alguém do time precisa olhar o detalhe.
        redirect_to sncr_numberings_path,
                    alert: report_sncr_error(
                      e,
                      category: "sncr_numbering_request",
                      alert: "Não foi possível obter numeração do SNCR agora. " \
                             "Tente novamente em instantes; se o erro persistir, nosso time já foi avisado.",
                      sncr_type: sncr_type
                    )
      rescue ActiveRecord::RecordNotUnique
        redirect_to sncr_numberings_path, alert: "Essas numerações já haviam sido importadas."
      end

      private

      def valid_type?(sncr_type)
        ::Prescription::SNCR_TYPES.include?(sncr_type)
      end

      def request_batch!(sncr_type)
        ::Sncr::NumberingBatch.request!(
          doctor_profile: doctor_profile,
          sncr_type: sncr_type,
          origin: "manual",
          user: current_user,
          access_token: access_token
        )
      end

      def success_notice(request, return_to)
        parts = [ "#{request.imported_count} numeração(ões) de #{request.sncr_type} obtidas do SNCR." ]
        parts << "Saldo na Anvisa: #{request.remote_balance}." if request.remote_balance.present?
        parts << "Você já pode assinar o documento." if return_to.present?
        parts.join(" ")
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
        @access_token = token_store.read unless defined?(@access_token)
        @access_token
      end

      def token_store
        @token_store ||= ::Sncr::TokenStore.new(user_id: current_user.id)
      end
    end
  end
end
