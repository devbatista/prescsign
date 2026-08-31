module App
  # Doctor self-profile ("me") within the panel (app.prescsign.local). Mirrors
  # V1::DoctorsController#show/update, reusing DoctorProfilePolicy. Only users
  # with a doctor profile can edit; others see a friendly empty state.
  class ProfileController < ApplicationController
    before_action :set_profile

    def show
      authorize @profile if @profile
    end

    def edit
      return redirect_to profile_path, alert: "Seu usuário não possui perfil profissional." if @profile.nil?

      authorize @profile
      @profile.doctor_specialties.build
      @specialties = Specialty.active.order(:name)
    end

    def update
      return redirect_to profile_path, alert: "Seu usuário não possui perfil profissional." if @profile.nil?

      authorize @profile
      user_attrs = user_params
      user_attrs = user_attrs.except(:password, :password_confirmation) if user_attrs[:password].blank?

      ActiveRecord::Base.transaction do
        current_user.update!(user_attrs) if user_attrs.present?
        @profile.license_organization_id = current_organization.id
        @profile.update!(profile_params)
      end

      redirect_to profile_path, notice: "Perfil atualizado."
    rescue ActiveRecord::RecordInvalid
      @profile.doctor_specialties.build if @profile.doctor_specialties.empty?
      @specialties = Specialty.active.order(:name)
      flash.now[:alert] = (@profile.errors.full_messages + current_user.errors.full_messages).to_sentence
      render :edit, status: :unprocessable_content
    end

    private

    def set_profile
      @profile = current_user.doctor_profile
    end

    def profile_params
      params.require(:doctor).permit(
        :full_name, :cpf, :license_number, :license_state, :gender,
        doctor_specialties_attributes: %i[id specialty_name rqe_number _destroy]
      )
    end

    def user_params
      params.require(:doctor).permit(:email, :password, :password_confirmation)
    end
  end
end
