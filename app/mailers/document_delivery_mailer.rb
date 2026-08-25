class DocumentDeliveryMailer < ApplicationMailer
  def notify_document
    @document = params.fetch(:document)
    @validation_url = Documents::PatientLinks.validation_url(@document)
    @download_url = Documents::PatientLinks.download_url(@document)
    @download_ttl_days = Document::PATIENT_DOWNLOAD_TTL.in_days.to_i

    mail(
      to: params.fetch(:recipient),
      from: Mailers::SenderAddress.on_behalf_of(doctor_display_name),
      subject: "Seu documento #{@document.code} está pronto"
    )
  end

  private

  # O paciente reconhece o médico, não a plataforma: o From: sai como
  # "Dr. Fulano via PrescSign". Sem perfil de médico, cai no institucional.
  def doctor_display_name
    @document.user&.doctor_profile&.display_name
  end
end
