module V1
  class DoctorsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_tenant_context!

    def show
      profile = current_user.doctor_profile
      return render_error("Doctor profile not found for current user", status: :not_found) if profile.nil?

      authorize profile, policy_class: DoctorProfilePolicy
      render_success(data: doctor_payload(profile))
    end

    def update
      profile = current_user.doctor_profile
      return render_error("Doctor profile not found for current user", status: :not_found) if profile.nil?

      authorize profile, policy_class: DoctorProfilePolicy

      user_attrs = user_update_params
      doctor_attrs = doctor_update_params

      if user_attrs[:password].blank?
        user_attrs.delete(:password)
        user_attrs.delete(:password_confirmation)
      end

      ActiveRecord::Base.transaction do
        current_user.update!(user_attrs) if user_attrs.present?
        profile.update!(doctor_attrs) if doctor_attrs.present?
      end

      render_success(data: doctor_payload(profile.reload))
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.record.errors.full_messages, status: :unprocessable_content)
    end

    def destroy
      profile = current_user.doctor_profile
      return head :no_content if profile.nil?

      authorize profile, policy_class: DoctorProfilePolicy
      current_user.update!(status: "inactive")
      profile.update!(active: false)
      head :no_content
    end

    private

    def user_update_params
      attrs = params.fetch(:doctor, {}).permit(:email, :password, :password_confirmation).to_h
      attrs.symbolize_keys
    end

    def doctor_update_params
      params.fetch(:doctor, {}).permit(
        :full_name,
        :cpf,
        :license_number,
        :license_state,
        :specialty
      )
    end

    def doctor_payload(profile)
      profile.slice(
        :id,
        :full_name,
        :email,
        :license_number,
        :license_state,
        :specialty,
        :active,
        :created_at,
        :updated_at
      ).merge(
        current_organization_id: current_user.current_organization_id,
        cpf_masked: masked_cpf(profile.cpf)
      )
    end

    def masked_cpf(cpf)
      digits = cpf.to_s.gsub(/\D/, "")
      return nil if digits.length < 11

      "***.***.***-#{digits[-2, 2]}"
    end
  end
end
