module V1
  class DoctorsController < ApplicationController
    before_action :authenticate_doctor!
    before_action :ensure_tenant_context!

    def show
      authorize current_doctor, policy_class: DoctorPolicy
      render_success(data: doctor_payload(current_doctor))
    end

    def update
      authorize current_doctor, policy_class: DoctorPolicy
      if current_doctor.update(doctor_update_params)
        render_success(data: doctor_payload(current_doctor))
      else
        render_error(current_doctor.errors.full_messages, status: :unprocessable_content)
      end
    end

    def destroy
      authorize current_doctor, policy_class: DoctorPolicy
      current_doctor.update!(active: false)
      head :no_content
    end

    private

    def doctor_update_params
      attrs = params.require(:doctor).permit(
        :full_name,
        :email,
        :license_number,
        :license_state,
        :specialty,
        :password,
        :password_confirmation
      )

      if attrs[:password].blank?
        attrs.delete(:password)
        attrs.delete(:password_confirmation)
      end

      attrs
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
