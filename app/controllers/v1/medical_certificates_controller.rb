module V1
  class MedicalCertificatesController < ApplicationController
    before_action :authenticate_doctor!
    before_action :ensure_tenant_context!
    before_action :set_medical_certificate, only: %i[show update revoke pdf]

    def show
      authorize @medical_certificate
      lifecycle_service.log_viewed!(
        resource: @medical_certificate,
        patient: @medical_certificate.patient,
        document: @medical_certificate.document,
        details: { context: "medical_certificates_show" }
      )
      render_success(data: medical_certificate_payload(@medical_certificate))
    end

    def create
      patient = policy_scope(Patient).find(medical_certificate_create_params[:patient_id])
      unit = unit_from_params
      medical_certificate = current_doctor.medical_certificates.new(
        medical_certificate_create_params.except(:patient_id, :unit_id).merge(
          patient: patient,
          organization: current_organization,
          code: generate_code(MedicalCertificate),
          status: "draft"
        )
      )
      authorize medical_certificate

      ActiveRecord::Base.transaction do
        medical_certificate.save!
        lifecycle_service.create_with_initial_version!(
          doctor: current_doctor,
          patient: patient,
          documentable: medical_certificate,
          unit: unit,
          kind: "medical_certificate",
          issued_on: medical_certificate.issued_on,
          content: medical_certificate.content
        )
      end

      render_success(data: medical_certificate_payload(medical_certificate.reload), status: :created)
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.record.errors.full_messages, status: :unprocessable_content)
    end

    def update
      authorize @medical_certificate
      return render_update_locked unless updatable_before_signature?(@medical_certificate)

      before_data = @medical_certificate.attributes.slice("content", "issued_on", "rest_start_on", "rest_end_on", "icd_code")

      ActiveRecord::Base.transaction do
        @medical_certificate.update!(medical_certificate_update_params)
        lifecycle_service.append_version_from_content!(
          document: @medical_certificate.document,
          content: @medical_certificate.content
        )
        lifecycle_service.log_updated!(
          resource: @medical_certificate,
          patient: @medical_certificate.patient,
          document: @medical_certificate.document,
          before_data: before_data,
          after_data: @medical_certificate.attributes.slice("content", "issued_on", "rest_start_on", "rest_end_on", "icd_code")
        )
      end

      render_success(data: medical_certificate_payload(@medical_certificate.reload))
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.record.errors.full_messages, status: :unprocessable_content)
    end

    def revoke
      authorize @medical_certificate, :revoke?

      lifecycle_service.revoke!(
        documentable: @medical_certificate,
        reason: revoke_params[:reason]
      )

      render_success(data: medical_certificate_payload(@medical_certificate.reload))
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.record.errors.full_messages, status: :unprocessable_content)
    end

    def pdf
      authorize @medical_certificate
      document = @medical_certificate.document
      latest_version = document.document_versions.find_by!(version_number: document.current_version)

      html = ActionController::Base.renderer.render(
        template: "v1/medical_certificates/pdf",
        layout: "pdf",
        locals: {
          medical_certificate: @medical_certificate,
          doctor: @medical_certificate.doctor,
          patient: @medical_certificate.patient,
          document: document,
          latest_version: latest_version,
          validation_url: public_validation_service.validation_url(document),
          validation_qr_svg: public_validation_service.qr_svg(document)
        }
      )

      pdf_binary = WickedPdf.new.pdf_from_string(
        html,
        page_size: "A4",
        margin: { top: 12, right: 10, bottom: 12, left: 10 },
        encoding: "UTF-8"
      )
      latest_version&.attach_pdf!(pdf_binary)

      send_data pdf_binary,
                filename: "atestado-#{@medical_certificate.code}-v#{document.current_version}.pdf",
                type: "application/pdf",
                disposition: "inline"
    end

    private

    def set_medical_certificate
      @medical_certificate = policy_scope(MedicalCertificate)
                            .includes(:patient, :doctor, :organization, document: :document_versions)
                            .find(params[:id])
    end

    # Payload contract for medical certificate creation.
    def medical_certificate_create_params
      params.require(:medical_certificate).permit(:patient_id, :unit_id, :content, :issued_on, :rest_start_on, :rest_end_on, :icd_code)
    end

    def medical_certificate_update_params
      params.require(:medical_certificate).permit(:content, :issued_on, :rest_start_on, :rest_end_on, :icd_code)
    end

    def revoke_params
      params.fetch(:revoke, {}).permit(:reason)
    end

    def updatable_before_signature?(medical_certificate)
      medical_certificate.status == "draft"
    end

    def render_update_locked
      render_error("Medical certificate can only be updated before signature", status: :unprocessable_content)
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
      unit_id = medical_certificate_create_params[:unit_id]
      return current_organization.default_unit if unit_id.blank?

      current_organization.units.find(unit_id)
    end

    def medical_certificate_payload(medical_certificate)
      document = medical_certificate.document
      {
        medical_certificate: medical_certificate.slice(
          :id, :organization_id, :doctor_id, :patient_id, :code, :content, :issued_on, :rest_start_on, :rest_end_on, :icd_code, :status, :created_at, :updated_at
        ),
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
  end
end
