# Web password recovery (session layer). Reuses Devise :recoverable.
# The JWT API keeps its own V1::Auth::PasswordsController untouched.
class PasswordsController < ApplicationController
  layout "auth"
  skip_before_action :authenticate_user!

  # GET /esqueci-senha
  def new
  end

  # POST /esqueci-senha
  def create
    email = params.dig(:user, :email).to_s.strip.downcase
    User.send_reset_password_instructions(email: email) if email.present?

    # Always generic, to avoid user enumeration.
    redirect_to new_user_session_path,
      notice: "Se este e-mail estiver cadastrado, enviamos as instruções de redefinição."
  end

  # GET /redefinir-senha?reset_password_token=...
  def edit
    @token = params[:reset_password_token].to_s
    redirect_to new_user_password_path, alert: "Link de redefinição inválido." if @token.blank?
  end

  # PUT /redefinir-senha
  def update
    user = User.reset_password_by_token(reset_params)

    if user.persisted? && user.errors.empty?
      # Accounts created by the organization responsible arrive unconfirmed and
      # set their first password through this same flow — confirm them here.
      user.update_columns(confirmed_at: Time.current) if user.respond_to?(:confirmed_at) && user.confirmed_at.blank?

      redirect_to new_user_session_path, notice: "Senha atualizada. Entre com a nova senha."
    else
      @token = reset_params[:reset_password_token]
      flash.now[:alert] = user.errors.full_messages.to_sentence.presence || "Não foi possível redefinir a senha."
      render :edit, status: :unprocessable_content
    end
  end

  private

  def reset_params
    params.require(:user).permit(:reset_password_token, :password, :password_confirmation)
  end
end
