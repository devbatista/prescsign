module App
  # Authenticated landing page (app.prescsign.local), routed by persona.
  class DashboardController < ApplicationController
    before_action :ensure_active_organization!

    def show
      @persona = current_persona

      patients = policy_scope(Patient)
      @patients_total = patients.count
      @patients_active = patients.where(active: true).count
      @recent_patients = patients.order(created_at: :desc).limit(5)
      @recent_doctors = recent_doctors
    end

    private

    def recent_doctors
      return DoctorProfile.none unless current_organization

      user_ids = OrganizationMembership
                   .where(organization_id: current_organization.id, role: "doctor", status: "active")
                   .pluck(:user_id)
      DoctorProfile.where(user_id: user_ids).order(created_at: :desc).limit(5)
    rescue StandardError
      DoctorProfile.none
    end
  end
end
