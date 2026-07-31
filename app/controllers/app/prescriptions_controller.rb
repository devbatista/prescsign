require "timeout"

module App
  # Prescription issuance within the panel (app.prescsign.local). Mirrors
  # V1::PrescriptionsController, reusing PrescriptionPolicy and the document
  # lifecycle service. Creating a prescription also creates its Document +
  # initial version; the panel then redirects to the document hub.
  class PrescriptionsController < ApplicationController
    before_action :ensure_active_organization!
    before_action :set_patients_for_select, only: %i[new create edit update]
    before_action :set_medications_for_select, only: %i[new create edit update]
    before_action :set_prescription, only: %i[edit update revoke pdf]

    def new
      @prescription = current_user.prescriptions.new(patient_id: params[:patient_id], issued_on: Date.current)
      authorize @prescription
    end

    def create
      patient = policy_scope(Patient).find(prescription_create_params[:patient_id])
      @prescription = current_user.prescriptions.new(
        prescription_create_params.except(:patient_id).merge(
          patient: patient,
          organization: current_organization,
          code: generate_code(Prescription),
          status: "draft"
        )
      )
      authorize @prescription

      ActiveRecord::Base.transaction do
        @prescription.save!
        lifecycle_service.create_with_initial_version!(
          user: current_user,
          patient: patient,
          documentable: @prescription,
          unit: current_organization.default_unit,
          kind: "prescription",
          issued_on: @prescription.issued_on,
          content: @prescription.content
        )
      end

      redirect_to document_path(@prescription.reload.document), notice: "Receita emitida com sucesso."
    rescue ActiveRecord::RecordInvalid
      flash.now[:alert] = @prescription.errors.full_messages.to_sentence
      render :new, status: :unprocessable_entity
    end

    def edit
      authorize @prescription
      return redirect_locked unless draft?
    end

    def update
      authorize @prescription
      return redirect_locked unless draft?

      before_data = @prescription.attributes.slice("content", "issued_on", "valid_until")

      ActiveRecord::Base.transaction do
        @prescription.update!(prescription_update_params)
        lifecycle_service.append_version_from_content!(document: @prescription.document, content: @prescription.content)
        lifecycle_service.log_updated!(
          resource: @prescription, patient: @prescription.patient, document: @prescription.document,
          before_data: before_data,
          after_data: @prescription.attributes.slice("content", "issued_on", "valid_until")
        )
      end

      redirect_to document_path(@prescription.document), notice: "Receita atualizada."
    rescue ActiveRecord::RecordInvalid
      flash.now[:alert] = @prescription.errors.full_messages.to_sentence
      render :edit, status: :unprocessable_entity
    end

    def revoke
      authorize @prescription, :revoke?
      lifecycle_service.revoke!(documentable: @prescription, reason: params[:reason])
      redirect_to document_path(@prescription.document), notice: "Receita revogada."
    end

    def pdf
      authorize @prescription, :pdf?
      document = @prescription.document
      latest_version = document.document_versions.find_by!(version_number: document.current_version)
      filename = "receita-#{@prescription.code}-v#{document.current_version}.pdf"

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
      redirect_to document_path(@prescription.document), alert: "A geração do PDF excedeu o tempo limite."
    end

    private

    def set_prescription
      @prescription = policy_scope(Prescription)
                      .includes(:patient, :organization, { user: :doctor_profile }, document: :document_versions)
                      .find(params[:id])
    end

    def set_patients_for_select
      @patients = policy_scope(Patient).where(active: true).order(:full_name)
    end

    def set_medications_for_select
      @medications = Medication.active.ordered
    end

    PRESCRIPTION_ITEM_PARAMS = [
      :id, :name, :active_ingredient, :strength, :quantity, :posology, :medication_id, :position, :_destroy
    ].freeze

    def prescription_create_params
      params.require(:prescription).permit(
        :patient_id, :content, :issued_on, :valid_until, :sncr_type,
        prescription_items_attributes: PRESCRIPTION_ITEM_PARAMS
      )
    end

    def prescription_update_params
      params.require(:prescription).permit(
        :content, :issued_on, :valid_until,
        prescription_items_attributes: PRESCRIPTION_ITEM_PARAMS
      )
    end

    def draft?
      @prescription.status == "draft"
    end

    def redirect_locked
      redirect_to document_path(@prescription.document), alert: "A receita só pode ser editada antes da assinatura."
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
