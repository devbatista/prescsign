module Public
  # Download público (sem auth) do PDF assinado, via token assinado e com
  # expiração. O link é enviado ao paciente ao assinar o documento. Mantém o dado
  # sensível fora do email (só o token trafega); token inválido/expirado -> 404.
  class DocumentDownloadsController < ActionController::Base
    protect_from_forgery with: :exception
    layout "public"

    def show
      document = Document.find_signed(params[:token], purpose: Document::PATIENT_DOWNLOAD_PURPOSE)
      version = document&.signed_pdf_version

      return render_unavailable if document.nil? || document.signed_at.blank? || version&.pdf_file&.attached? != true

      send_data version.pdf_file.download,
                filename: "#{document.kind}-#{document.code}.pdf",
                type: "application/pdf",
                disposition: "inline"
    end

    private

    # Token inválido/expirado ou PDF ausente — não distingue os casos (evita
    # vazar se um documento existe) e orienta a revalidar pelo código.
    def render_unavailable
      render "unavailable", status: :not_found
    end
  end
end
