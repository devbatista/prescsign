require "timeout"

module V1
  class PrescriptionsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_tenant_context!
    before_action :set_prescription, only: %i[show update revoke pdf]

    def show
      authorize @prescription
      lifecycle_service.log_viewed!(
        resource: @prescription,
        patient: @prescription.patient,
        document: @prescription.document,
        details: { context: "prescriptions_show" }
      )
      render_success(data: prescription_payload(@prescription))
    end

    def create
      with_idempotency(scope: "prescriptions#create") do
        patient = policy_scope(Patient).find(prescription_create_params[:patient_id])
        unit = unit_from_params
        prescription = current_user.prescriptions.new(
          prescription_create_params.except(:patient_id, :unit_id).merge(
            doctor: current_doctor_for_context,
            patient: patient,
            organization: current_organization,
            code: generate_code(Prescription),
            status: "draft"
          )
        )
        authorize prescription

        ActiveRecord::Base.transaction do
          prescription.save!
          lifecycle_service.create_with_initial_version!(
            user: current_user,
            doctor: current_doctor_for_context,
            patient: patient,
            documentable: prescription,
            unit: unit,
            kind: "prescription",
            issued_on: prescription.issued_on,
            content: prescription.content
          )
        end

        render_success(data: prescription_payload(prescription.reload), status: :created)
      end
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.record.errors.full_messages, status: :unprocessable_content)
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

      render_success(data: prescription_payload(@prescription.reload))
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.record.errors.full_messages, status: :unprocessable_content)
    end

    def revoke
      with_idempotency(scope: "prescriptions#revoke") do
        authorize @prescription, :revoke?

        lifecycle_service.revoke!(
          documentable: @prescription,
          reason: revoke_params[:reason]
        )

        render_success(data: prescription_payload(@prescription.reload))
      end
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.record.errors.full_messages, status: :unprocessable_content)
    end

    def pdf
      authorize @prescription
      document = @prescription.document
      latest_version = document.document_versions.find_by!(version_number: document.current_version)

      html = ActionController::Base.renderer.render(
        template: "v1/prescriptions/pdf",
        layout: "pdf",
        locals: {
          prescription: @prescription,
          doctor: @prescription.doctor,
          patient: @prescription.patient,
          document: document,
          latest_version: latest_version,
          validation_url: public_validation_service.validation_url(document),
          validation_qr_svg: public_validation_service.qr_svg(document)
        }
      )

      pdf_binary = generate_pdf_with_timeout(html)
      latest_version&.attach_pdf!(pdf_binary)

      send_data pdf_binary,
                filename: "receita-#{@prescription.code}-v#{document.current_version}.pdf",
                type: "application/pdf",
                disposition: "inline"
    rescue Timeout::Error
      render_error("PDF generation timed out", status: :gateway_timeout)
    end

    private

    def set_prescription
      @prescription = policy_scope(Prescription)
                      .includes(:patient, :doctor, :organization, document: :document_versions)
                      .find(params[:id])
    end

    # Payload contract for prescription creation.
    def prescription_create_params
      params.require(:prescription).permit(:patient_id, :unit_id, :content, :issued_on, :valid_until)
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
      render_error("Prescription can only be updated before signature", status: :unprocessable_content)
    end

    def lifecycle_service
      @lifecycle_service ||= Documents::LifecycleService.new(
        actor: current_user,
        request_id: request.request_id,
        request_origin: request.base_url,
        ip_address: request.remote_ip,
        user_agent: request.user_agent
      )
    end

    def public_validation_service
      @public_validation_service ||= Documents::PublicValidationService.new(base_url: request.base_url)
    end

    def generate_code(model_class)
      loop do
        code = SecureRandom.alphanumeric(10).upcase
        return code unless model_class.exists?(code: code)
      end
    end

    def unit_from_params
      unit_id = prescription_create_params[:unit_id]
      return current_organization.default_unit if unit_id.blank?

      current_organization.units.find(unit_id)
    end

    def prescription_payload(prescription)
      document = prescription.document
      {
        prescription: prescription.slice(:id, :organization_id, :user_id, :doctor_id, :patient_id, :code, :content, :issued_on, :valid_until, :status, :created_at, :updated_at),
        document: document.slice(:id, :organization_id, :unit_id, :code, :kind, :status, :current_version, :issued_on, :cancelled_at, :created_at, :updated_at),
        latest_version: latest_version_payload(document)
      }
    end

    def latest_version_payload(document)
      latest_version = document.document_versions.order(version_number: :desc).first
      return nil if latest_version.nil?

      latest_version.slice(:id, :version_number, :checksum, :generated_at).merge(
        pdf_signed_url: latest_version.pdf_signed_url,
        pdf_signed_url_expires_in: latest_version.pdf_signed_url_expires_in
      )
    end

    def generate_pdf_with_timeout(html)
      Timeout.timeout(pdf_generation_timeout_seconds) do
        WickedPdf.new.pdf_from_string(
          html,
          page_size: "A4",
          margin: { top: 12, right: 10, bottom: 12, left: 10 },
          encoding: "UTF-8"
        )
      end
    end

    def pdf_generation_timeout_seconds
      configured = Rails.application.config.x.pdf_generation_timeout_seconds.to_f
      configured.positive? ? configured : 20.0
    end
  end
end
