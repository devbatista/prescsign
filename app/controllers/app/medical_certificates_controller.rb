require "timeout"

module App
  # Medical certificate issuance within the panel (app.prescsign.local). Mirrors
  # V1::MedicalCertificatesController, reusing MedicalCertificatePolicy and the
  # document lifecycle service. Creation also creates the Document + version.
  class MedicalCertificatesController < ApplicationController
    before_action :ensure_active_organization!
    before_action :set_patients_for_select, only: %i[new create edit update]
    before_action :set_medical_certificate, only: %i[edit update revoke pdf]

    def new
      @medical_certificate = current_user.medical_certificates.new(
        patient_id: params[:patient_id], issued_on: Date.current, rest_start_on: Date.current
      )
      authorize @medical_certificate
    end

    def create
      patient = policy_scope(Patient).find(medical_certificate_create_params[:patient_id])
      @medical_certificate = current_user.medical_certificates.new(
        medical_certificate_create_params.except(:patient_id).merge(
          patient: patient,
          organization: current_organization,
          code: generate_code(MedicalCertificate),
          status: "draft"
        )
      )
      authorize @medical_certificate

      ActiveRecord::Base.transaction do
        @medical_certificate.save!
        lifecycle_service.create_with_initial_version!(
          user: current_user,
          patient: patient,
          documentable: @medical_certificate,
          unit: current_organization.default_unit,
          kind: "medical_certificate",
          issued_on: @medical_certificate.issued_on,
          content: @medical_certificate.content
        )
      end

      redirect_to document_path(@medical_certificate.reload.document), notice: "Atestado emitido com sucesso."
    rescue ActiveRecord::RecordInvalid
      flash.now[:alert] = @medical_certificate.errors.full_messages.to_sentence
      render :new, status: :unprocessable_content
    end

    def edit
      authorize @medical_certificate
      return redirect_locked unless draft?
    end

    def update
      authorize @medical_certificate
      return redirect_locked unless draft?

      before_data = @medical_certificate.attributes.slice("content", "issued_on", "rest_start_on", "rest_end_on", "icd_code")

      ActiveRecord::Base.transaction do
        @medical_certificate.update!(medical_certificate_update_params)
        lifecycle_service.append_version_from_content!(document: @medical_certificate.document, content: @medical_certificate.content)
        lifecycle_service.log_updated!(
          resource: @medical_certificate, patient: @medical_certificate.patient, document: @medical_certificate.document,
          before_data: before_data,
          after_data: @medical_certificate.attributes.slice("content", "issued_on", "rest_start_on", "rest_end_on", "icd_code")
        )
      end

      redirect_to document_path(@medical_certificate.document), notice: "Atestado atualizado."
    rescue ActiveRecord::RecordInvalid
      flash.now[:alert] = @medical_certificate.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_content
    end

    def revoke
      authorize @medical_certificate, :revoke?

      reason = params[:reason].to_s.strip
      if reason.blank?
        return redirect_to document_path(@medical_certificate.document), alert: "Informe o motivo da revogação."
      end

      lifecycle_service.revoke!(documentable: @medical_certificate, reason: reason)
      redirect_to document_path(@medical_certificate.document), notice: "Atestado revogado."
    end

    def pdf
      authorize @medical_certificate, :pdf?
      document = @medical_certificate.document
      latest_version = document.document_versions.find_by!(version_number: document.current_version)
      filename = "atestado-#{@medical_certificate.code}-v#{document.current_version}.pdf"

      # Documento assinado: servir o PDF assinado já armazenado na versão atual.
      # Não re-renderizar (perderia a assinatura e sobrescreveria o anexo).
      if document.signed_at.present? && latest_version&.pdf_file&.attached?
        return send_data latest_version.pdf_file.download,
                         filename: filename, type: "application/pdf", disposition: "inline"
      end

      # Rascunho: renderiza o preview na hora e guarda na versão atual.
      pdf_binary = Documents::PdfRenderer.new(document: document, base_url: request.base_url).render
      latest_version&.attach_pdf!(pdf_binary)

      send_data pdf_binary,
                filename: filename,
                type: "application/pdf",
                disposition: "inline"
    rescue Timeout::Error
      redirect_to document_path(@medical_certificate.document), alert: "A geração do PDF excedeu o tempo limite."
    end

    private

    def set_medical_certificate
      @medical_certificate = policy_scope(MedicalCertificate)
                             .includes(:patient, :organization, { user: :doctor_profile }, document: :document_versions)
                             .find(params[:id])
    end

    def set_patients_for_select
      @patients = policy_scope(Patient).where(active: true).order(:full_name)
    end

    def medical_certificate_create_params
      params.require(:medical_certificate).permit(:patient_id, :content, :issued_on, :rest_start_on, :rest_days, :icd_code)
    end

    def medical_certificate_update_params
      params.require(:medical_certificate).permit(:content, :issued_on, :rest_start_on, :rest_days, :icd_code)
    end

    def draft?
      @medical_certificate.status == "draft"
    end

    def redirect_locked
      redirect_to document_path(@medical_certificate.document), alert: "O atestado só pode ser editado antes da assinatura."
    end

    def generate_code(model_class)
      loop do
        code = SecureRandom.alphanumeric(10).upcase
        return code unless model_class.exists?(code: code)
      end
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
  end
end
