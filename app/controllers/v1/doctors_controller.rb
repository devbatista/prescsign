module V1
  class DoctorsController < ApplicationController
    before_action :authenticate_user!
    before_action :ensure_tenant_context!

    def show
      doctor = current_doctor_for_context
      return render_error("Doctor profile not found for current user", status: :not_found) if doctor.nil?

      authorize doctor, policy_class: DoctorPolicy
      render_success(data: doctor_payload(doctor))
    end

    def update
      doctor = current_doctor_for_context
      return render_error("Doctor profile not found for current user", status: :not_found) if doctor.nil?

      authorize doctor, policy_class: DoctorPolicy

      user_attrs = user_update_params
      doctor_attrs = doctor_update_params

      if user_attrs[:password].blank?
        user_attrs.delete(:password)
        user_attrs.delete(:password_confirmation)
      end

      ActiveRecord::Base.transaction do
        current_user.update!(user_attrs) if user_attrs.present?
        doctor.update!(doctor_attrs) if doctor_attrs.present?
      end

      render_success(data: doctor_payload(doctor.reload))
    rescue ActiveRecord::RecordInvalid => e
      render_error(e.record.errors.full_messages, status: :unprocessable_content)
    end

    def destroy
      doctor = current_doctor_for_context
      return head :no_content if doctor.nil?

      authorize doctor, policy_class: DoctorPolicy
      current_user.update!(status: "inactive")
      doctor.update!(active: false)
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
        :license_number,
        :license_state,
        :specialty
      )
    end

    def doctor_payload(doctor)
      doctor.slice(
        :id,
        :current_organization_id,
        :full_name,
        :email,
        :license_number,
        :license_state,
        :specialty,
        :active,
        :created_at,
        :updated_at
      ).merge(cpf_masked: doctor.masked_cpf)
    end
  end
end
