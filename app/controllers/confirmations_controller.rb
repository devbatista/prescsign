# Web account confirmation (session layer). Reuses Devise :confirmable.
# The confirmation email links here (web_user_confirmation_url).
class ConfirmationsController < WebBaseController
  layout "auth"
  skip_before_action :authenticate_user!

  # GET /confirmar-conta?confirmation_token=...
  def show
    user = User.confirm_by_token(params[:confirmation_token].to_s)

    if user.errors.empty?
      redirect_to new_user_session_path, notice: "E-mail confirmado! Agora você pode entrar."
    else
      redirect_to new_user_session_path,
        alert: "Não foi possível confirmar: #{user.errors.full_messages.to_sentence}"
    end
  end

  # GET /reenviar-confirmacao
  def new
  end

  # POST /reenviar-confirmacao
  def create
    email = params.dig(:user, :email).to_s.strip.downcase
    User.send_confirmation_instructions(email: email) if email.present?

    redirect_to new_user_session_path,
      notice: "Se a conta existir e estiver pendente, reenviamos a confirmação."
  end
end
