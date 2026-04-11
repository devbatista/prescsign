module V1
  class PrescriptionsController < ApplicationController
    before_action :authenticate_doctor!
    before_action :set_prescription, only: %i[show update revoke pdf]

    def show
      authorize @prescription
      render json: prescription_payload(@prescription), status: :ok
    end

    def create
      patient = current_doctor.patients.find(prescription_create_params[:patient_id])
      prescription = current_doctor.prescriptions.new(
        prescription_create_params.except(:patient_id).merge(
          patient: patient,
          code: generate_code(Prescription),
          status: "draft"
        )
      )
      authorize prescription

      ActiveRecord::Base.transaction do
        prescription.save!
        lifecycle_service.create_with_initial_version!(
          doctor: current_doctor,
          patient: patient,
          documentable: prescription,
          kind: "prescription",
          issued_on: prescription.issued_on,
          content: prescription.content
        )
      end

      render json: prescription_payload(prescription.reload), status: :created
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
    end

    def update
      authorize @prescription
      return render_update_locked unless updatable_before_signature?(@prescription)

      before_data = @prescription.attributes.slice("content", "issued_on", "valid_until")

      ActiveRecord::Base.transaction do
        @prescription.update!(prescription_update_params)
        lifecycle_service.append_version_from_content!(
          document: @prescription.document,
          content: @prescription.content
        )
        lifecycle_service.log_updated!(
          resource: @prescription,
          patient: @prescription.patient,
          document: @prescription.document,
          before_data: before_data,
          after_data: @prescription.attributes.slice("content", "issued_on", "valid_until")
        )
      end

      render json: prescription_payload(@prescription.reload), status: :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
    end

    def revoke
      authorize @prescription, :revoke?

      lifecycle_service.revoke!(
        documentable: @prescription,
        reason: revoke_params[:reason]
      )

      render json: prescription_payload(@prescription.reload), status: :ok
    rescue ActiveRecord::RecordInvalid => e
      render json: { errors: e.record.errors.full_messages }, status: :unprocessable_content
    end

    def pdf
      authorize @prescription
      document = @prescription.document
      latest_version = document.document_versions.order(version_number: :desc).first

      html = ActionController::Base.renderer.render(
        template: "v1/prescriptions/pdf",
        layout: "pdf",
        locals: {
          prescription: @prescription,
          doctor: @prescription.doctor,
          patient: @prescription.patient,
          document: document,
          latest_version: latest_version,
          validation_url: "#{request.base_url}/v1/documents/#{document.id}"
        }
      )

      pdf_binary = WickedPdf.new.pdf_from_string(
        html,
        page_size: "A4",
        margin: { top: 12, right: 10, bottom: 12, left: 10 },
        encoding: "UTF-8"
      )

      send_data pdf_binary,
                filename: "receita-#{@prescription.code}-v#{document.current_version}.pdf",
                type: "application/pdf",
                disposition: "inline"
    end

    private

    def set_prescription
      @prescription = policy_scope(Prescription).find(params[:id])
    end

    # Payload contract for prescription creation.
    def prescription_create_params
      params.require(:prescription).permit(:patient_id, :content, :issued_on, :valid_until)
    end

    def prescription_update_params
      params.require(:prescription).permit(:content, :issued_on, :valid_until)
    end

    def revoke_params
      params.fetch(:revoke, {}).permit(:reason)
    end

    def updatable_before_signature?(prescription)
      prescription.status == "draft"
    end

    def render_update_locked
      render json: { error: "Prescription can only be updated before signature" }, status: :unprocessable_content
    end

    def lifecycle_service
      @lifecycle_service ||= Documents::LifecycleService.new(
        actor: current_doctor,
        request_id: request.request_id,
        request_origin: request.base_url,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end

    def generate_code(model_class)
      loop do
        code = SecureRandom.alphanumeric(10).upcase
        return code unless model_class.exists?(code: code)
      end
    end

    def prescription_payload(prescription)
      document = prescription.document
      {
        prescription: prescription.slice(:id, :doctor_id, :patient_id, :code, :content, :issued_on, :valid_until, :status, :created_at, :updated_at),
        document: document.slice(:id, :code, :kind, :status, :current_version, :issued_on, :cancelled_at, :created_at, :updated_at),
        latest_version: document.document_versions.order(version_number: :desc).first&.slice(:id, :version_number, :checksum, :generated_at)
      }
    end
  end
end
