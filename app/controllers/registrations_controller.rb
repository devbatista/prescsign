# Web registration for the organization responsible (invitation-based).
# Logic mirrors V1::Auth::RegistrationsController#create (kept until Fase 5, when the
# API is removed and this can be backed by a shared service).
class RegistrationsController < ApplicationController
  layout "auth"
  skip_before_action :authenticate_user!

  DOCTOR_PROFILE_FIELDS = %i[cpf license_number license_state specialty gender].freeze

  # GET /cadastro?invitation_token=...
  def new
    @token = params[:invitation_token].to_s
    @invitation = OrganizationRegistrationInvitation.find_pending_by_raw_token(@token) if @token.present?
    @invited_email = @invitation&.invited_email
  end

  # POST /cadastro
  def create
    @token = params[:invitation_token].to_s
    @invitation = OrganizationRegistrationInvitation.find_pending_by_raw_token(@token)
    return render_invalid_invitation if @invitation.nil?

    email = @invitation.invited_email.to_s.downcase
    @invited_email = email

    user = User.new(
      email: email,
      password: user_params[:password],
      password_confirmation: user_params[:password_confirmation],
      status: "active"
    )
    @include_doctor_profile = params[:include_doctor_profile].present?
    profile = build_doctor_profile(user, email) if @include_doctor_profile

    return rerender(user.errors.full_messages) unless user.valid?
    return rerender(profile.errors.full_messages) if profile && !profile.valid?

    ActiveRecord::Base.transaction do
      user.skip_confirmation_notification!
      user.save!
      profile&.save!

      link_specialty!(profile) if profile

      ensure_role!(user, "manager")
      ensure_role!(user, "doctor") if profile

      OrganizationMembership.create!(user: user, organization: @invitation.organization, role: "admin", status: "active")
      OrganizationResponsible.find_or_create_by!(organization: @invitation.organization, user: user)
      user.update_column(:current_organization_id, @invitation.organization_id)
      @invitation.mark_accepted!(user: user)

      user.send_confirmation_instructions
    end

    redirect_to new_user_session_path,
      notice: "Cadastro concluído! Confirme seu e-mail para acessar."
  rescue StandardError => e
    Rails.logger.error("[RegistrationsController#create] #{e.class}: #{e.message}")
    rerender("Não foi possível concluir o cadastro. Tente novamente.")
  end

  private

  def user_params
    params.fetch(:user, {}).permit(:full_name, :password, :password_confirmation)
  end

  def build_doctor_profile(user, email)
    attrs = params.fetch(:doctor_profile, {}).permit(*DOCTOR_PROFILE_FIELDS)
    DoctorProfile.new(
      user: user,
      full_name: user_params[:full_name],
      email: email,
      cpf: attrs[:cpf].to_s.gsub(/\D/, ""),
      license_number: attrs[:license_number].to_s.strip.upcase,
      license_state: attrs[:license_state].to_s.strip.upcase,
      gender: attrs[:gender],
      active: true
    )
  end

  # Optional: if the responsible declares a specialty while registering as a
  # doctor, resolve it to the catalog (find-or-create) and link it.
  def link_specialty!(profile)
    name = params.dig(:doctor_profile, :specialty).to_s.strip
    return if name.blank?

    specialty = Specialty.find_or_create_by_name!(name)
    profile.doctor_specialties.create!(specialty: specialty) if specialty
  end

  def ensure_role!(user, role_name)
    role = user.user_roles.find_or_initialize_by(role: role_name)
    role.status = "active"
    role.save! if role.new_record? || role.changed?
  end

  def render_invalid_invitation
    flash.now[:alert] = "Convite inválido, expirado ou já utilizado."
    render :new, status: :unprocessable_entity
  end

  def rerender(messages)
    flash.now[:alert] = Array(messages).to_sentence.presence || "Não foi possível concluir o cadastro."
    render :new, status: :unprocessable_entity
  end
end
