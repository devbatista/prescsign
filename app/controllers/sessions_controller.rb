# Session-based (cookie) login for the web layer. Coexists with the JWT API auth
# in V1::Auth::SessionsController, which stays untouched during the migration.
class SessionsController < ApplicationController
  layout "auth"

  skip_before_action :authenticate_user!, only: %i[new create]

  def new
    redirect_to after_sign_in_path_for(current_user) if user_signed_in?
  end

  def create
    user = User.find_for_database_authentication(email: login_params[:email].to_s.strip.downcase)

    unless user&.valid_password?(login_params[:password])
      return render_invalid("E-mail ou senha inválidos.")
    end

    return render_invalid("Confirme seu e-mail antes de entrar.") unless user.confirmed?
    return render_invalid("Conta inativa.") unless user.status == "active"

    # Explicit :user scope — the User model also maps to :api_user (JWT). Implicit
    # sign_in would pick the wrong scope and authenticate_user! (scope :user) would fail.
    sign_in(:user, user)
    set_initial_organization_context(user)
    # Cross-subdomain redirect (login. -> app.) needs allow_other_host.
    redirect_options = { allow_other_host: true }
    redirect_options[:notice] = "Bem-vindo(a) de volta." unless session[:organization_selection_required]
    redirect_to after_sign_in_path_for(user), **redirect_options
  end

  def destroy
    session.delete(:current_organization_id)
    session.delete(:organization_selection_required)
    sign_out(:user)
    redirect_to new_user_session_url(subdomain: "login"), allow_other_host: true, notice: "Você saiu da sua conta."
  end

  private

  def login_params
    params.fetch(:user, {}).permit(:email, :password)
  end

  def set_initial_organization_context(user)
    memberships = user.organization_memberships.active
                      .joins(:organization)
                      .merge(Organization.where(active: true))

    if memberships.many?
      session.delete(:current_organization_id)
      session[:organization_selection_required] = true
    else
      session[:current_organization_id] = memberships.first&.organization_id
      session.delete(:organization_selection_required)
    end
  end

  # After login, cross over to the panel subdomain.
  def after_sign_in_path_for(_user)
    app_root_url(subdomain: "app")
  end

  def render_invalid(message)
    flash.now[:alert] = message
    @email = login_params[:email]
    render :new, status: :unprocessable_content
  end
end
