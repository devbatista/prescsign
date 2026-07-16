module App
  # Doctors management within the panel (app.prescsign.local). The organization
  # responsible creates doctors directly (name, CRM, specialties + RQE): the
  # account is created unconfirmed and the doctor receives an email to set their
  # own password. Gated by AccessContext#can?(:doctors).
  class DoctorsController < ApplicationController
    before_action :ensure_active_organization!
    before_action :require_responsible_management!

    def index
      load_doctors
    end

    def new
      @profile = DoctorProfile.new
      @profile.doctor_specialties.build
      @specialties = Specialty.active.order(:name)
    end

    def create
      result = Doctors::CreationService.new(
        organization: current_organization,
        email: params[:email],
        profile_attributes: profile_params,
        invited_by: current_user
      ).call

      if result.success?
        redirect_to doctors_path,
          notice: success_message(result)
      else
        @profile = result.profile
        @profile.doctor_specialties.build if @profile.doctor_specialties.empty?
        @specialties = Specialty.active.order(:name)
        @email = params[:email]
        flash.now[:alert] = @profile.errors.full_messages.to_sentence.presence || "Não foi possível cadastrar o médico."
        render :new, status: :unprocessable_entity
      end
    end

    private

    def require_responsible_management!
      render_forbidden unless access_context.can?(:doctors)
    end

    def success_message(result)
      return "Médico vinculado a esta clínica." if result.linked?

      "Médico cadastrado. Enviamos um e-mail para #{result.user.email} definir a senha."
    end

    def load_doctors
      user_ids = OrganizationMembership
                 .where(organization_id: current_organization.id, role: "doctor", status: "active")
                 .pluck(:user_id)
      scope = DoctorProfile.where(user_id: user_ids).includes(:specialties).order(:full_name)
      @doctors, @page, @total_pages, @total = paginate(scope)
    end

    def profile_params
      params.require(:doctor_profile).permit(
        :full_name, :cpf, :license_number, :license_state, :gender,
        doctor_specialties_attributes: %i[id specialty_name rqe_number _destroy]
      )
    end
  end
end
